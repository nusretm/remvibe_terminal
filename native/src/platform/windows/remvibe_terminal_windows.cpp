#include "remvibe_terminal_windows.h"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <deque>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

// Extracted from remvibe_update_center (frozen reference HEAD be22cf19).
// Only local ConPTY/process ownership belongs to this library. No Fleet/RPC.
struct rvterm_session {
  HPCON pseudo_console = nullptr;
  HANDLE input_write = nullptr;
  HANDLE output_read = nullptr;
  HANDLE process = nullptr;
  HANDLE job = nullptr;
  std::thread reader;
  std::mutex mutex;
  std::deque<uint8_t> output;
  size_t maximum_buffer_bytes = 0;
  std::atomic<bool> closing{false};
  std::atomic<bool> eof{false};
  std::atomic<bool> overflow{false};
};

namespace {

int32_t error_code(DWORD value = GetLastError()) {
  return value == ERROR_SUCCESS ? ERROR_GEN_FAILURE
                                : static_cast<int32_t>(value);
}

void close_handle(HANDLE& handle) {
  if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
    CloseHandle(handle);
  }
  handle = nullptr;
}

void reader_main(rvterm_session* session) {
  uint8_t buffer[4096];
  while (!session->closing.load()) {
    DWORD read = 0;
    if (!ReadFile(session->output_read, buffer, sizeof(buffer), &read, nullptr)) {
      const DWORD error = GetLastError();
      if (error != ERROR_BROKEN_PIPE && error != ERROR_OPERATION_ABORTED &&
          !session->closing.load()) {
        session->overflow.store(true);
      }
      break;
    }
    if (read == 0) break;
    bool exceeded = false;
    {
      std::lock_guard<std::mutex> lock(session->mutex);
      if (read > session->maximum_buffer_bytes ||
          session->output.size() > session->maximum_buffer_bytes - read) {
        exceeded = true;
      } else {
        session->output.insert(session->output.end(), buffer, buffer + read);
      }
    }
    if (exceeded) {
      session->overflow.store(true);
      if (session->job != nullptr) {
        TerminateJobObject(session->job, ERROR_BUFFER_OVERFLOW);
      }
      break;
    }
  }
  session->eof.store(true);
}

void destroy_session(rvterm_session* session) {
  if (session == nullptr) return;
  session->closing.store(true);
  close_handle(session->input_write);
  if (session->job != nullptr) {
    TerminateJobObject(session->job, ERROR_CANCELLED);
  } else if (session->process != nullptr) {
    // Failed creation before job assignment must not orphan the child.
    TerminateProcess(session->process, ERROR_CANCELLED);
  }
  if (session->pseudo_console != nullptr) {
    ClosePseudoConsole(session->pseudo_console);
    session->pseudo_console = nullptr;
  }
  if (session->reader.joinable()) {
    // std::thread owns the Win32 thread handle; no unsynchronized OpenThread.
    CancelSynchronousIo(session->reader.native_handle());
  }
  close_handle(session->output_read);
  if (session->reader.joinable()) session->reader.join();
  close_handle(session->process);
  close_handle(session->job);
  delete session;
}

}  // namespace

extern "C" {

int32_t rvterm_create(
    const wchar_t* command_line,
    uint16_t columns,
    uint16_t rows,
    size_t maximum_buffer_bytes,
    rvterm_session** out_session) {
  if (out_session != nullptr) *out_session = nullptr;
  if (command_line == nullptr || command_line[0] == L'\0' ||
      columns == 0 || rows == 0 || columns > 32767 || rows > 32767 ||
      maximum_buffer_bytes == 0 || out_session == nullptr) {
    return ERROR_INVALID_PARAMETER;
  }
  auto* session = new (std::nothrow) rvterm_session();
  if (session == nullptr) return ERROR_OUTOFMEMORY;
  session->maximum_buffer_bytes = maximum_buffer_bytes;

  HANDLE input_read = nullptr;
  HANDLE output_write = nullptr;
  if (!CreatePipe(&input_read, &session->input_write, nullptr, 0) ||
      !CreatePipe(&session->output_read, &output_write, nullptr, 0)) {
    const int32_t error = error_code();
    close_handle(input_read);
    close_handle(output_write);
    destroy_session(session);
    return error;
  }

  const COORD size = {
      static_cast<SHORT>(columns), static_cast<SHORT>(rows)};
  const HRESULT pseudo_result = CreatePseudoConsole(
      size, input_read, output_write, 0, &session->pseudo_console);
  close_handle(input_read);
  close_handle(output_write);
  if (FAILED(pseudo_result)) {
    const int32_t error = static_cast<int32_t>(HRESULT_CODE(pseudo_result));
    destroy_session(session);
    return error;
  }

  SIZE_T attribute_size = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_size);
  std::vector<uint8_t> attributes(attribute_size);
  auto* attribute_list = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(
      attributes.data());
  if (!InitializeProcThreadAttributeList(
          attribute_list, 1, 0, &attribute_size)) {
    const int32_t error = error_code();
    destroy_session(session);
    return error;
  }
  if (!UpdateProcThreadAttribute(
          attribute_list, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
          session->pseudo_console, sizeof(session->pseudo_console),
          nullptr, nullptr)) {
    const int32_t error = error_code();
    DeleteProcThreadAttributeList(attribute_list);
    destroy_session(session);
    return error;
  }

  STARTUPINFOEXW startup{};
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.lpAttributeList = attribute_list;
  PROCESS_INFORMATION process{};
  std::wstring mutable_command(command_line);
  const BOOL created = CreateProcessW(
      nullptr, mutable_command.data(), nullptr, nullptr, FALSE,
      EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
      nullptr, nullptr, &startup.StartupInfo, &process);
  const int32_t create_error = created ? ERROR_SUCCESS : error_code();
  DeleteProcThreadAttributeList(attribute_list);
  if (!created) {
    destroy_session(session);
    return create_error;
  }
  CloseHandle(process.hThread);
  session->process = process.hProcess;

  session->job = CreateJobObjectW(nullptr, nullptr);
  if (session->job == nullptr) {
    const int32_t error = error_code();
    destroy_session(session);
    return error;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(
          session->job, JobObjectExtendedLimitInformation,
          &limits, sizeof(limits)) ||
      !AssignProcessToJobObject(session->job, session->process)) {
    const int32_t error = error_code();
    destroy_session(session);
    return error;
  }

  try {
    session->reader = std::thread(reader_main, session);
  } catch (...) {
    destroy_session(session);
    return ERROR_NOT_ENOUGH_MEMORY;
  }
  *out_session = session;
  return ERROR_SUCCESS;
}

int32_t rvterm_write(
    rvterm_session* session, const uint8_t* bytes, size_t length) {
  if (session == nullptr || (bytes == nullptr && length != 0) ||
      session->closing.load()) {
    return ERROR_INVALID_PARAMETER;
  }
  size_t offset = 0;
  while (offset < length) {
    DWORD written = 0;
    const DWORD chunk = static_cast<DWORD>(
        std::min<size_t>(length - offset, static_cast<size_t>(0x7fffffff)));
    if (!WriteFile(
            session->input_write, bytes + offset, chunk, &written, nullptr)) {
      return error_code();
    }
    if (written == 0) return ERROR_WRITE_FAULT;
    offset += written;
  }
  return ERROR_SUCCESS;
}

int32_t rvterm_resize(
    rvterm_session* session, uint16_t columns, uint16_t rows) {
  if (session == nullptr || columns == 0 || rows == 0 ||
      columns > 32767 || rows > 32767 || session->closing.load()) {
    return ERROR_INVALID_PARAMETER;
  }
  const HRESULT result = ResizePseudoConsole(
      session->pseudo_console,
      {static_cast<SHORT>(columns), static_cast<SHORT>(rows)});
  return FAILED(result) ? static_cast<int32_t>(HRESULT_CODE(result))
                        : ERROR_SUCCESS;
}

int32_t rvterm_read(
    rvterm_session* session, uint8_t* buffer, size_t capacity,
    size_t* out_length, int32_t* out_eof, int32_t* out_overflow) {
  if (session == nullptr || buffer == nullptr || capacity == 0 ||
      out_length == nullptr || out_eof == nullptr || out_overflow == nullptr) {
    return ERROR_INVALID_PARAMETER;
  }
  std::lock_guard<std::mutex> lock(session->mutex);
  const size_t count = std::min(capacity, session->output.size());
  for (size_t index = 0; index < count; ++index) {
    buffer[index] = session->output.front();
    session->output.pop_front();
  }
  *out_length = count;
  *out_eof = session->eof.load() && session->output.empty() ? 1 : 0;
  *out_overflow = session->overflow.load() ? 1 : 0;
  return ERROR_SUCCESS;
}

int32_t rvterm_ctrl_c(rvterm_session* session) {
  const uint8_t control_c = 0x03;
  return rvterm_write(session, &control_c, 1);
}

int32_t rvterm_wait(
    rvterm_session* session, uint32_t timeout_ms,
    int32_t* out_exited, int32_t* out_exit_code) {
  if (session == nullptr || out_exited == nullptr || out_exit_code == nullptr) {
    return ERROR_INVALID_PARAMETER;
  }
  const DWORD wait = WaitForSingleObject(session->process, timeout_ms);
  if (wait == WAIT_TIMEOUT) {
    *out_exited = 0;
    *out_exit_code = 0;
    return ERROR_SUCCESS;
  }
  if (wait != WAIT_OBJECT_0) return error_code();
  DWORD exit_code = 0;
  if (!GetExitCodeProcess(session->process, &exit_code)) return error_code();
  *out_exited = 1;
  *out_exit_code = static_cast<int32_t>(exit_code);
  return ERROR_SUCCESS;
}

int32_t rvterm_process_id(
    rvterm_session* session, uint32_t* out_process_id) {
  if (session == nullptr || out_process_id == nullptr ||
      session->process == nullptr) return ERROR_INVALID_PARAMETER;
  const DWORD pid = GetProcessId(session->process);
  if (pid == 0) return error_code();
  *out_process_id = static_cast<uint32_t>(pid);
  return ERROR_SUCCESS;
}

int32_t rvterm_close(rvterm_session* session) {
  if (session == nullptr) return ERROR_INVALID_PARAMETER;
  destroy_session(session);
  return ERROR_SUCCESS;
}

}  // extern "C"

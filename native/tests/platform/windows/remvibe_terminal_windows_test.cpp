#include "remvibe_terminal_windows.h"

#include <windows.h>

#include <chrono>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

bool run_command(
    rvterm_session* session, const std::string& command,
    const std::string& marker) {
  if (rvterm_write(session, reinterpret_cast<const uint8_t*>(command.data()),
                   command.size()) != 0) {
    return false;
  }
  std::string output;
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::seconds(25);
  std::vector<uint8_t> buffer(4096);
  while (std::chrono::steady_clock::now() < deadline) {
    size_t length = 0;
    int32_t eof = 0;
    int32_t overflow = 0;
    if (rvterm_read(session, buffer.data(), buffer.size(), &length,
                    &eof, &overflow) != 0 || overflow != 0) {
      return false;
    }
    output.append(reinterpret_cast<const char*>(buffer.data()), length);
    if (output.find(marker) != std::string::npos) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  std::cerr << "Missing marker " << marker << " in output:\n" << output;
  return false;
}

}  // namespace

int main() {
  rvterm_session* first = nullptr;
  rvterm_session* second = nullptr;
  const wchar_t* command = L"powershell.exe -NoLogo -NoProfile";
  if (rvterm_create(command, 100, 30, 256 * 1024, &first) != 0 ||
      rvterm_create(command, 100, 30, 256 * 1024, &second) != 0) {
    std::cerr << "ConPTY creation failed.\n";
    if (first != nullptr) rvterm_close(first);
    if (second != nullptr) rvterm_close(second);
    return 1;
  }
  uint32_t first_pid = 0;
  uint32_t second_pid = 0;
  if (rvterm_process_id(first, &first_pid) != 0 ||
      rvterm_process_id(second, &second_pid) != 0 ||
      first_pid == second_pid || first_pid == 0 || second_pid == 0) {
    rvterm_close(first);
    rvterm_close(second);
    std::cerr << "Distinct process IDs not observed.\n";
    return 1;
  }
  HANDLE first_process = OpenProcess(SYNCHRONIZE, FALSE, first_pid);
  if (first_process == nullptr) {
    rvterm_close(first);
    rvterm_close(second);
    return 1;
  }
  const bool first_ok = run_command(
      first, "Write-Output ('RVTERM-' + 'FIRST')\r", "RVTERM-FIRST");
  const bool second_ok = run_command(
      second, "Write-Output ('RVTERM-' + 'SECOND')\r", "RVTERM-SECOND");
  const bool resized = rvterm_resize(second, 120, 40) == 0;

  rvterm_close(first);
  const bool first_terminated =
      WaitForSingleObject(first_process, 10000) == WAIT_OBJECT_0;
  CloseHandle(first_process);
  const bool independent = run_command(
      second, "Write-Output ('RVTERM-' + 'ALIVE')\r", "RVTERM-ALIVE");
  const std::string exit_command = "exit\r";
  rvterm_write(second,
      reinterpret_cast<const uint8_t*>(exit_command.data()),
      exit_command.size());
  int32_t exited = 0;
  int32_t exit_code = -1;
  for (int attempt = 0; attempt < 100 && exited == 0; ++attempt) {
    if (rvterm_wait(second, 100, &exited, &exit_code) != 0) break;
  }
  rvterm_close(second);
  if (!first_ok || !second_ok || !resized || !first_terminated ||
      !independent || exited == 0 || exit_code != 0) {
    std::cerr << "ConPTY two-session lifecycle failed.\n";
    return 1;
  }
  std::cout << "TERM-01A native PowerShell two-session smoke PASS.\n";
  return 0;
}

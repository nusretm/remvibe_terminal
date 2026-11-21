#include "remvibe_terminal_linux.h"

#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <new>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// Native Linux PTY. Dart's owning isolate serializes all native operations.
// A PTY child is its own session/process-group leader; a viewer never owns it.
namespace {
struct Session {
  int master = -1;
  pid_t pid = -1;
  bool exited = false;
  int exit_code = 0;
  bool eof = false;
};

int child_exit_code(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return 255;
}

void stop_and_reap(Session* session) {
  if (!session->exited && session->pid > 0) {
    // Terminate the PTY child process group, not unrelated system processes.
    if (kill(-session->pid, SIGKILL) != 0 && errno == ESRCH) {
      kill(session->pid, SIGKILL);
    }
    int status = 0;
    pid_t reaped;
    do {
      reaped = waitpid(session->pid, &status, 0);
    } while (reaped < 0 && errno == EINTR);
    if (reaped == session->pid) {
      session->exit_code = child_exit_code(status);
    }
    session->exited = true;
  }
  if (session->master >= 0) {
    close(session->master);
    session->master = -1;
  }
}
}  // namespace

extern "C" {
int rvterm_linux_create(const char* command, uint16_t columns, uint16_t rows,
                        size_t max_buffer_bytes, void** out_session) {
  if (!command || !*command || !out_session || columns == 0 || rows == 0 ||
      max_buffer_bytes == 0) return EINVAL;
  *out_session = nullptr;
  struct winsize size {};
  size.ws_col = columns;
  size.ws_row = rows;
  int master = -1;
  pid_t pid = forkpty(&master, nullptr, nullptr, &size);
  if (pid < 0) return errno;
  if (pid == 0) {
    // In the forked Dart VM child, exec immediately; no Dart runtime work.
    execl("/bin/sh", "sh", "-c", command, static_cast<char*>(nullptr));
    _exit(127);
  }
  int flags = fcntl(master, F_GETFL);
  if (flags < 0 || fcntl(master, F_SETFL, flags | O_NONBLOCK) < 0) {
    const int saved = errno;
    Session failed {master, pid};
    stop_and_reap(&failed);
    return saved;
  }
  auto* session = new (std::nothrow) Session {master, pid};
  if (!session) {
    Session failed {master, pid};
    stop_and_reap(&failed);
    return ENOMEM;
  }
  *out_session = session;
  return 0;
}

int rvterm_linux_process_id(void* handle, uint32_t* out_pid) {
  if (!handle || !out_pid) return EINVAL;
  *out_pid = static_cast<uint32_t>(static_cast<Session*>(handle)->pid);
  return 0;
}

int rvterm_linux_write(void* handle, const uint8_t* bytes, size_t length) {
  if (!handle || (length != 0 && !bytes)) return EINVAL;
  auto* s = static_cast<Session*>(handle);
  size_t sent = 0;
  while (sent < length) {
    const ssize_t n = write(s->master, bytes + sent, length - sent);
    if (n > 0) {
      sent += static_cast<size_t>(n);
      continue;
    }
    if (n < 0 && errno == EINTR) continue;
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      // Retry boundedly, rather than silently dropping part of the input.
      struct pollfd fd {s->master, POLLOUT, 0};
      const int ready = poll(&fd, 1, 100);
      if (ready > 0) continue;
      return ready == 0 ? EAGAIN : errno;
    }
    return n == 0 ? EIO : errno;
  }
  return 0;
}

int rvterm_linux_resize(void* handle, uint16_t columns, uint16_t rows) {
  if (!handle || columns == 0 || rows == 0) return EINVAL;
  auto* s = static_cast<Session*>(handle);
  struct winsize size {};
  size.ws_col = columns;
  size.ws_row = rows;
  return ioctl(s->master, TIOCSWINSZ, &size) == 0 ? 0 : errno;
}

int rvterm_linux_ctrl_c(void* handle) {
  const uint8_t etx = 3;  // PTY line discipline dispatches SIGINT to foreground.
  return rvterm_linux_write(handle, &etx, 1);
}

int rvterm_linux_read(void* handle, uint8_t* out_bytes, size_t capacity,
                      size_t* out_length, int* out_eof, int* out_overflow) {
  if (!handle || !out_bytes || !out_length || !out_eof || !out_overflow ||
      capacity == 0) return EINVAL;
  auto* s = static_cast<Session*>(handle);
  *out_length = 0;
  *out_eof = s->eof ? 1 : 0;
  *out_overflow = 0;  // Linux kernel PTY buffering is bounded, not our ring.
  if (s->eof) return 0;
  ssize_t n;
  do {
    n = read(s->master, out_bytes, capacity);
  } while (n < 0 && errno == EINTR);
  if (n > 0) {
    *out_length = static_cast<size_t>(n);
    return 0;
  }
  if (n == 0 || (n < 0 && errno == EIO)) {
    s->eof = true;
    *out_eof = 1;
    return 0;
  }
  if (errno == EAGAIN || errno == EWOULDBLOCK) return 0;
  return errno;
}

int rvterm_linux_wait(void* handle, uint32_t timeout_ms,
                      int* out_exited, int* out_exit_code) {
  if (!handle || !out_exited || !out_exit_code) return EINVAL;
  auto* s = static_cast<Session*>(handle);
  *out_exited = s->exited ? 1 : 0;
  *out_exit_code = s->exit_code;
  if (s->exited) return 0;
  const int checks = timeout_ms == 0 ? 1 :
      static_cast<int>((static_cast<uint64_t>(timeout_ms) + 9) / 10);
  for (int i = 0; i < checks; ++i) {
    int status = 0;
    pid_t r;
    do {
      r = waitpid(s->pid, &status, WNOHANG);
    } while (r < 0 && errno == EINTR);
    if (r == s->pid) {
      s->exited = true;
      s->exit_code = child_exit_code(status);
      *out_exited = 1;
      *out_exit_code = s->exit_code;
      return 0;
    }
    if (r < 0) return errno;
    if (timeout_ms == 0) return 0;
    usleep(10000);
  }
  return 0;
}

int rvterm_linux_close(void* handle) {
  if (!handle) return EINVAL;
  auto* s = static_cast<Session*>(handle);
  stop_and_reap(s);
  delete s;
  return 0;
}
}  // extern "C"

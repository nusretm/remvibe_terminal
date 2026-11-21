#include "remvibe_terminal_linux.h"

#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <new>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// Native Linux PTY. Dart's owning isolate serializes all native operations.
// A PTY child is its own session/process-group leader; a viewer never owns it.
// Dart's SIGCHLD handler may reap children it did not create. The direct
// parent of the actual PTY shell is therefore a tiny native supervisor, not
// the Dart VM. The supervisor reports Bash's true exit code over a socket.
namespace {
struct Session {
  int master = -1;
  int status_fd = -1;
  pid_t pid = -1;
  bool exited = false;
  int exit_code = 0;
  bool eof = false;
};

struct StatusMessage {
  int kind;
  int value;
};
constexpr int kReady = 1;
constexpr int kExit = 2;
constexpr int kFailure = 3;

int child_exit_code(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return 255;
}

void report(int fd, int kind, int value) {
  const StatusMessage message{kind, value};
  // Do not deliver SIGPIPE if the owning Dart process already closed the PTY.
  ssize_t result;
  do {
    result = send(fd, &message, sizeof(message), MSG_NOSIGNAL);
  } while (result < 0 && errno == EINTR);
}

[[noreturn]] void supervise(int master, int slave, int parent_fd,
                            int status_fd, const char* command) {
  close(parent_fd);
  close(master);
  const pid_t child = fork();
  if (child == 0) {
    close(status_fd);
    if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0 ||
        dup2(slave, STDIN_FILENO) < 0 ||
        dup2(slave, STDOUT_FILENO) < 0 ||
        dup2(slave, STDERR_FILENO) < 0) {
      _exit(126);
    }
    if (slave > STDERR_FILENO) close(slave);
    execl("/bin/sh", "sh", "-c", command, static_cast<char*>(nullptr));
    _exit(127);
  }
  close(slave);
  if (child < 0) {
    report(status_fd, kFailure, errno);
    close(status_fd);
    _exit(1);
  }
  report(status_fd, kReady, static_cast<int>(child));
  int status = 0;
  pid_t reaped;
  do {
    reaped = waitpid(child, &status, 0);
  } while (reaped < 0 && errno == EINTR);
  report(status_fd, reaped == child ? kExit : kFailure,
         reaped == child ? child_exit_code(status) : errno);
  close(status_fd);
  _exit(reaped == child ? 0 : 1);
}

void stop(Session* s) {
  if (!s->exited && s->pid > 0) {
    // The shell is a session/process-group leader created by setsid().
    if (kill(-s->pid, SIGKILL) != 0 && errno == ESRCH) {
      kill(s->pid, SIGKILL);
    }
  }
  if (s->master >= 0) {
    close(s->master);
    s->master = -1;
  }
  if (s->status_fd >= 0) {
    close(s->status_fd);
    s->status_fd = -1;
  }
}
}  // namespace

extern "C" {
int rvterm_linux_create(const char* command, uint16_t columns, uint16_t rows,
                        size_t max_buffer_bytes, void** out_session) {
  if (!command || !*command || !out_session || columns == 0 || rows == 0 ||
      max_buffer_bytes == 0) return EINVAL;
  *out_session = nullptr;
  struct winsize size{};
  size.ws_col = columns;
  size.ws_row = rows;
  int master = -1;
  int slave = -1;
  if (openpty(&master, &slave, nullptr, nullptr, &size) < 0) return errno;
  int sockets[2] = {-1, -1};
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) < 0) {
    const int error = errno;
    close(slave); close(master);
    return error;
  }
  const pid_t supervisor = fork();
  if (supervisor < 0) {
    const int error = errno;
    close(sockets[0]); close(sockets[1]);
    close(slave); close(master);
    return error;
  }
  if (supervisor == 0) {
    supervise(master, slave, sockets[0], sockets[1], command);
  }
  close(slave);
  close(sockets[1]);
  StatusMessage message{};
  ssize_t received;
  do {
    received = recv(sockets[0], &message, sizeof(message), 0);
  } while (received < 0 && errno == EINTR);
  if (received != static_cast<ssize_t>(sizeof(message)) ||
      message.kind != kReady || message.value <= 0) {
    const int error = received == static_cast<ssize_t>(sizeof(message)) &&
        message.kind == kFailure ? message.value : ECHILD;
    close(sockets[0]); close(master);
    // A failed helper will exit by itself; the Dart VM owns its reap.
    return error;
  }
  const int master_flags = fcntl(master, F_GETFL);
  const int status_flags = fcntl(sockets[0], F_GETFL);
  if (master_flags < 0 || status_flags < 0 ||
      fcntl(master, F_SETFL, master_flags | O_NONBLOCK) < 0 ||
      fcntl(sockets[0], F_SETFL, status_flags | O_NONBLOCK) < 0) {
    const int error = errno;
    Session failed{master, sockets[0], static_cast<pid_t>(message.value)};
    stop(&failed);
    return error;
  }
  auto* session = new (std::nothrow) Session{
    master, sockets[0], static_cast<pid_t>(message.value)
  };
  if (!session) {
    Session failed{master, sockets[0], static_cast<pid_t>(message.value)};
    stop(&failed);
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
  const uint32_t checks = timeout_ms == 0 ? 1 : (timeout_ms + 9) / 10;
  for (uint32_t i = 0; i < checks; ++i) {
    StatusMessage message{};
    const ssize_t n = recv(s->status_fd, &message, sizeof(message), MSG_DONTWAIT);
    if (n == static_cast<ssize_t>(sizeof(message))) {
      if (message.kind == kExit) {
        s->exited = true;
        s->exit_code = message.value;
        *out_exited = 1;
        *out_exit_code = s->exit_code;
        return 0;
      }
      if (message.kind == kFailure) return message.value;
      return EPROTO;
    }
    if (n == 0) return ECHILD;  // Helper disappeared without exit report.
    if (n > 0) return EPROTO;
    if (errno == EINTR) continue;
    if (errno != EAGAIN && errno != EWOULDBLOCK) return errno;
    if (timeout_ms == 0) return 0;
    usleep(10000);
  }
  return 0;
}
int rvterm_linux_close(void* handle) {
  if (!handle) return EINVAL;
  auto* s = static_cast<Session*>(handle);
  stop(s);
  delete s;
  return 0;
}
}  // extern "C"

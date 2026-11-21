#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Linux PTY ABI. Return 0 for success; a positive errno for failure.
// The returned session is opaque and must be closed exactly once.
// Linux uses a single nonblocking PTY master and a process-group-owned child.
int rvterm_linux_create(const char* command, uint16_t columns, uint16_t rows,
                        size_t max_buffer_bytes, void** out_session);
int rvterm_linux_process_id(void* session, uint32_t* out_pid);
int rvterm_linux_write(void* session, const uint8_t* bytes, size_t length);
int rvterm_linux_resize(void* session, uint16_t columns, uint16_t rows);
int rvterm_linux_ctrl_c(void* session);
int rvterm_linux_read(void* session, uint8_t* out_bytes, size_t capacity,
                      size_t* out_length, int* out_eof, int* out_overflow);
int rvterm_linux_wait(void* session, uint32_t timeout_ms,
                      int* out_exited, int* out_exit_code);
int rvterm_linux_close(void* session);

#ifdef __cplusplus
}
#endif

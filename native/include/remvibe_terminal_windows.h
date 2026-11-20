#ifndef REMVIBE_TERMINAL_WINDOWS_H
#define REMVIBE_TERMINAL_WINDOWS_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define RVTERM_API __declspec(dllexport)
#else
#define RVTERM_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rvterm_session rvterm_session;

RVTERM_API int32_t rvterm_create(
    const wchar_t* command_line,
    uint16_t columns,
    uint16_t rows,
    size_t maximum_buffer_bytes,
    rvterm_session** out_session);
RVTERM_API int32_t rvterm_write(
    rvterm_session* session, const uint8_t* bytes, size_t length);
RVTERM_API int32_t rvterm_resize(
    rvterm_session* session, uint16_t columns, uint16_t rows);
RVTERM_API int32_t rvterm_read(
    rvterm_session* session,
    uint8_t* buffer,
    size_t capacity,
    size_t* out_length,
    int32_t* out_eof,
    int32_t* out_overflow);
RVTERM_API int32_t rvterm_ctrl_c(rvterm_session* session);
RVTERM_API int32_t rvterm_wait(
    rvterm_session* session,
    uint32_t timeout_ms,
    int32_t* out_exited,
    int32_t* out_exit_code);
// Added for independently verifying child-process cleanup.
RVTERM_API int32_t rvterm_process_id(
    rvterm_session* session, uint32_t* out_process_id);
RVTERM_API int32_t rvterm_close(rvterm_session* session);

#ifdef __cplusplus
}
#endif

#endif  // REMVIBE_TERMINAL_WINDOWS_H

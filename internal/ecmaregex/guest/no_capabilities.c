#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum { WASI_SUCCESS = 0, WASI_BADF = 8 };

int32_t __imported_wasi_snapshot_preview1_clock_time_get(
        int32_t id, int64_t precision, int32_t result_pointer) {
    (void)id;
    (void)precision;
    *(uint64_t *)(uintptr_t)(uint32_t)result_pointer = 0;
    return WASI_SUCCESS;
}

int32_t __imported_wasi_snapshot_preview1_random_get(int32_t buffer_pointer,
                                                     int32_t length) {
    memset((void *)(uintptr_t)(uint32_t)buffer_pointer, 0, (uint32_t)length);
    return WASI_SUCCESS;
}

int32_t __imported_wasi_snapshot_preview1_fd_close(int32_t fd) {
    (void)fd;
    return WASI_BADF;
}

int32_t __imported_wasi_snapshot_preview1_fd_fdstat_get(int32_t fd,
                                                        int32_t result_pointer) {
    (void)fd;
    (void)result_pointer;
    return WASI_BADF;
}

int32_t __imported_wasi_snapshot_preview1_fd_seek(
        int32_t fd, int64_t offset, int32_t whence, int32_t result_pointer) {
    (void)fd;
    (void)offset;
    (void)whence;
    (void)result_pointer;
    return WASI_BADF;
}

int32_t __imported_wasi_snapshot_preview1_fd_write(
        int32_t fd, int32_t iovs_pointer, int32_t iovs_length,
        int32_t result_pointer) {
    (void)fd;
    (void)iovs_pointer;
    (void)iovs_length;
    *(uint32_t *)(uintptr_t)(uint32_t)result_pointer = 0;
    return WASI_BADF;
}

#include "callback.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>

extern int navidromeGoCallback(uintptr_t handle, int value);

struct callback_args {
    uintptr_t handle;
    int value;
    int result;
};

static void *callback_thread(void *opaque) {
    struct callback_args *args = (struct callback_args *)opaque;
    args->result = navidromeGoCallback(args->handle, args->value);
    return NULL;
}

int run_callback_on_native_thread(uintptr_t handle, int value, int *callback_result) {
    pthread_t thread;
    struct callback_args args = {
        .handle = handle,
        .value = value,
        .result = -1,
    };
    int rc = pthread_create(&thread, NULL, callback_thread, &args);
    if (rc != 0) {
        return rc;
    }
    rc = pthread_join(thread, NULL);
    if (rc != 0) {
        return rc;
    }
    *callback_result = args.result;
    return 0;
}

uint64_t sum_bytes(const uint8_t *data, size_t length) {
    uint64_t sum = 0;
    for (size_t i = 0; i < length; i++) {
        sum += data[i];
    }
    return sum;
}

int open_readonly_for_errno_test(const char *path, int *error_number) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        *error_number = errno;
        return -1;
    }
    close(fd);
    *error_number = 0;
    return fd;
}

#ifndef NAVIDROME_IOS_P002_CALLBACK_H
#define NAVIDROME_IOS_P002_CALLBACK_H

#include <stddef.h>
#include <stdint.h>

int run_callback_on_native_thread(uintptr_t handle, int value, int *callback_result);
uint64_t sum_bytes(const uint8_t *data, size_t length);
int open_readonly_for_errno_test(const char *path, int *error_number);

#endif

#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum { THREADS = 4, ITERATIONS = 4000 };

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t protected_count;

static void *worker(void *unused) {
    (void)unused;
    for (int i = 0; i < ITERATIONS; i++) {
        int rc = pthread_mutex_lock(&lock);
        if (rc != 0) {
            return (void *)(intptr_t)rc;
        }
        protected_count++;
        rc = pthread_mutex_unlock(&lock);
        if (rc != 0) {
            return (void *)(intptr_t)rc;
        }
    }
    return NULL;
}

static int test_file_io(void) {
    const char *root = getenv("IOS_PROBE_TMPDIR");
    if (root == NULL || root[0] == '\0') {
        fprintf(stderr, "IOS_PROBE_TMPDIR is required\n");
        return 1;
    }

    char path[1024];
    int n = snprintf(path, sizeof(path), "%s/native-c-XXXXXX", root);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        fprintf(stderr, "temporary path is too long\n");
        return 1;
    }

    int fd = mkstemp(path);
    if (fd < 0) {
        fprintf(stderr, "mkstemp failed: %s\n", strerror(errno));
        return 1;
    }

    static const char expected[] = "navidrome-ios-p002";
    size_t written = 0;
    while (written < sizeof(expected)) {
        ssize_t nwrite = write(fd, expected + written, sizeof(expected) - written);
        if (nwrite < 0 && errno == EINTR) {
            continue;
        }
        if (nwrite <= 0) {
            fprintf(stderr, "write failed: %s\n", strerror(errno));
            close(fd);
            unlink(path);
            return 1;
        }
        written += (size_t)nwrite;
    }

    if (lseek(fd, 0, SEEK_SET) != 0) {
        fprintf(stderr, "lseek failed: %s\n", strerror(errno));
        close(fd);
        unlink(path);
        return 1;
    }

    char actual[sizeof(expected)];
    size_t read_count = 0;
    while (read_count < sizeof(actual)) {
        ssize_t nread = read(fd, actual + read_count, sizeof(actual) - read_count);
        if (nread < 0 && errno == EINTR) {
            continue;
        }
        if (nread <= 0) {
            fprintf(stderr, "read failed: %s\n", strerror(errno));
            close(fd);
            unlink(path);
            return 1;
        }
        read_count += (size_t)nread;
    }

    int close_rc = close(fd);
    int unlink_rc = unlink(path);
    if (close_rc != 0 || unlink_rc != 0 || memcmp(actual, expected, sizeof(expected)) != 0) {
        fprintf(stderr, "temporary file contents or cleanup did not match\n");
        return 1;
    }
    return 0;
}

static int test_monotonic_time(void) {
    struct timespec before;
    struct timespec after;
    if (clock_gettime(CLOCK_MONOTONIC, &before) != 0) {
        fprintf(stderr, "clock_gettime before failed: %s\n", strerror(errno));
        return 1;
    }
    if (clock_gettime(CLOCK_MONOTONIC, &after) != 0) {
        fprintf(stderr, "clock_gettime after failed: %s\n", strerror(errno));
        return 1;
    }
    if (after.tv_sec < before.tv_sec ||
        (after.tv_sec == before.tv_sec && after.tv_nsec < before.tv_nsec)) {
        fprintf(stderr, "CLOCK_MONOTONIC moved backwards\n");
        return 1;
    }
    return 0;
}

static int test_pthreads(void) {
    pthread_t threads[THREADS];
    int created = 0;
    for (; created < THREADS; created++) {
        int rc = pthread_create(&threads[created], NULL, worker, NULL);
        if (rc != 0) {
            fprintf(stderr, "pthread_create failed: %s\n", strerror(rc));
            break;
        }
    }

    int failed = created != THREADS;
    for (int i = 0; i < created; i++) {
        void *result = NULL;
        int rc = pthread_join(threads[i], &result);
        if (rc != 0 || result != NULL) {
            fprintf(stderr, "pthread_join/worker failed: %s\n",
                    rc == 0 ? "worker returned an error" : strerror(rc));
            failed = 1;
        }
    }
    if (failed || protected_count != (uint64_t)THREADS * ITERATIONS) {
        fprintf(stderr, "pthread result mismatch: count=%llu\n",
                (unsigned long long)protected_count);
        return 1;
    }
    return 0;
}

int main(void) {
    if (getpid() <= 0 || test_file_io() != 0 || test_monotonic_time() != 0 ||
        test_pthreads() != 0) {
        return 1;
    }
    printf("probe=native-c status=PASS threads=%d operations=%d\n",
           THREADS, THREADS * ITERATIONS);
    return 0;
}

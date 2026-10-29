package main

/*
#include <stdlib.h>
#include <string.h>

#include "callback.h"
*/
import "C"

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/cgo"
	"strconv"
	"syscall"
	"time"
	"unsafe"
)

//export navidromeGoCallback
func navidromeGoCallback(handle C.uintptr_t, value C.int) C.int {
	channel := cgo.Handle(handle).Value().(chan int)
	channel <- int(value)
	return value + 1
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func testNativeThreadCallback() {
	callbackValues := make(chan int, 1)
	handle := cgo.NewHandle(callbackValues)
	defer handle.Delete()

	var callbackResult C.int
	if rc := C.run_callback_on_native_thread(C.uintptr_t(handle), 41, &callbackResult); rc != 0 {
		fail("native pthread callback failed: %s", C.GoString(C.strerror(rc)))
	}
	if callbackResult != 42 {
		fail("C callback return mismatch: got=%d want=42", int(callbackResult))
	}
	select {
	case got := <-callbackValues:
		if got != 41 {
			fail("Go callback value mismatch: got=%d want=41", got)
		}
	case <-time.After(5 * time.Second):
		fail("Go callback did not return within the bound")
	}
}

func testGoPointerIsNotRetainedByC() {
	payload := []byte{3, 5, 7, 11, 13}
	sum := C.sum_bytes((*C.uint8_t)(unsafe.Pointer(&payload[0])), C.size_t(len(payload)))
	runtime.KeepAlive(payload)
	if uint64(sum) != 39 {
		fail("C memory-read checksum mismatch: got=%d want=39", uint64(sum))
	}
}

func testErrnoHandling() {
	root := os.Getenv("IOS_PROBE_TMPDIR")
	if root == "" {
		fail("IOS_PROBE_TMPDIR is required")
	}
	pathText := filepath.Join(root, "cgo-missing-"+strconv.Itoa(os.Getpid()))
	path := C.CString(pathText)
	defer C.free(unsafe.Pointer(path))

	var errorNumber C.int
	fd := C.open_readonly_for_errno_test(path, &errorNumber)
	if fd >= 0 {
		fail("opening a deliberately absent path unexpectedly succeeded")
	}
	err := syscall.Errno(errorNumber)
	if !errors.Is(err, syscall.ENOENT) {
		fail("C errno mismatch: got=%v want=%v", err, syscall.ENOENT)
	}
}

func main() {
	testNativeThreadCallback()
	testGoPointerIsNotRetainedByC()
	testErrnoHandling()
	fmt.Printf("probe=cgo-callback status=PASS\n")
}

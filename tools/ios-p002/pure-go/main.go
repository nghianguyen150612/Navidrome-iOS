package main

import (
	"bytes"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"
)

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func testGoroutinesAndChannels() {
	const workers = 8
	const sendsPerWorker = 64
	values := make(chan int, workers*sendsPerWorker)
	deadline := time.After(5 * time.Second)

	for worker := 0; worker < workers; worker++ {
		go func(base int) {
			for i := 0; i < sendsPerWorker; i++ {
				values <- base + i
			}
		}(worker * sendsPerWorker)
	}

	sum := 0
	for i := 0; i < workers*sendsPerWorker; i++ {
		select {
		case value := <-values:
			sum += value
		case <-deadline:
			fail("goroutine/channel workload timed out")
		}
	}
	expected := (workers*sendsPerWorker - 1) * (workers * sendsPerWorker) / 2
	if sum != expected {
		fail("goroutine/channel sum mismatch: got=%d want=%d", sum, expected)
	}
}

func testTimer() {
	timer := time.NewTimer(10 * time.Millisecond)
	defer timer.Stop()
	select {
	case <-timer.C:
	case <-time.After(3 * time.Second):
		fail("timer did not fire within the bound")
	}
}

func testGarbageCollection() {
	blocks := make([][]byte, 32)
	for i := range blocks {
		blocks[i] = bytes.Repeat([]byte{byte(i + 1)}, 1024)
	}
	runtime.GC()
	sum := 0
	for _, block := range blocks {
		sum += int(block[0])
	}
	runtime.KeepAlive(blocks)
	if sum != 528 {
		fail("retained allocation checksum mismatch: %d", sum)
	}
}

func testFilesystem() {
	root := os.Getenv("IOS_PROBE_TMPDIR")
	if root == "" {
		fail("IOS_PROBE_TMPDIR is required")
	}
	dir, err := os.MkdirTemp(root, "go-pure-")
	if err != nil {
		fail("MkdirTemp: %v", err)
	}
	defer os.RemoveAll(dir)

	path := filepath.Join(dir, "probe.txt")
	want := []byte("navidrome-ios-p002")
	if err := os.WriteFile(path, want, 0600); err != nil {
		fail("WriteFile: %v", err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		fail("ReadFile: %v", err)
	}
	if !bytes.Equal(got, want) {
		fail("filesystem contents did not match")
	}
	if err := os.Remove(path); err != nil {
		fail("Remove file: %v", err)
	}
}

func testSignal() {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGUSR1)
	defer signal.Stop(signals)

	if err := syscall.Kill(os.Getpid(), syscall.SIGUSR1); err != nil {
		fail("send SIGUSR1 to self: %v", err)
	}
	select {
	case received := <-signals:
		if received != syscall.SIGUSR1 {
			fail("received unexpected signal: %v", received)
		}
	case <-time.After(3 * time.Second):
		fail("did not receive SIGUSR1 within the bound")
	}
}

func main() {
	testGoroutinesAndChannels()
	testTimer()
	testGarbageCollection()
	testFilesystem()
	testSignal()
	fmt.Printf("probe=pure-go status=PASS gomaxprocs=%d\n", runtime.GOMAXPROCS(0))
}

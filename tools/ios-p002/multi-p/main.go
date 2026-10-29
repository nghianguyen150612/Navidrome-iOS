package main

import (
	"fmt"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

const (
	workers    = 8
	iterations = 4000
)

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func main() {
	want, err := strconv.Atoi(os.Getenv("GOMAXPROCS"))
	if err != nil || (want != 1 && want != 2) {
		fail("GOMAXPROCS must be exactly 1 or 2")
	}
	if got := runtime.GOMAXPROCS(0); got != want {
		fail("runtime GOMAXPROCS mismatch: got=%d want=%d", got, want)
	}

	var lock sync.Mutex
	var total uint64
	var completed atomic.Uint64
	start := make(chan struct{})
	done := make(chan struct{})
	var group sync.WaitGroup
	group.Add(workers)

	for worker := 0; worker < workers; worker++ {
		go func() {
			defer group.Done()
			<-start
			for i := 0; i < iterations; i++ {
				lock.Lock()
				total++
				lock.Unlock()
				if i%32 == 0 {
					runtime.Gosched()
				}
			}
			completed.Add(1)
		}()
	}
	go func() {
		group.Wait()
		close(done)
	}()
	close(start)

	select {
	case <-done:
	case <-time.After(15 * time.Second):
		fail("bounded lock/scheduler workload timed out")
	}
	if total != workers*iterations || completed.Load() != workers {
		fail("contention result mismatch: total=%d completed=%d", total, completed.Load())
	}

	timer := time.NewTimer(5 * time.Millisecond)
	select {
	case <-timer.C:
	case <-time.After(3 * time.Second):
		timer.Stop()
		fail("bounded timer workload timed out")
	}

	debug.FreeOSMemory()
	fmt.Printf("probe=multi-p status=PASS gomaxprocs=%d workers=%d lock_ops=%d\n",
		want, workers, total)
}

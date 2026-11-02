// engine_full_tunnel_test.go covers the outbound TUN writer's failure policy.
//
// A TUN write error used to terminate the drain goroutine permanently while
// Write kept reporting success, so after a single transient interface error
// (Wi-Fi <-> cellular handover, ENETDOWN) every outbound packet was silently
// discarded for the rest of the session and only a VPN restart recovered.
// These tests pin the self-healing behaviour instead.

package tunnel

import (
	"errors"
	"sync"
	"testing"
	"time"
)

// flakyWriter fails the first failCount writes, then succeeds.
type flakyWriter struct {
	mu        sync.Mutex
	failCount int
	writes    [][]byte
	failures  int
	started   chan struct{}
	once      sync.Once
}

func newFlakyWriter(failCount int) *flakyWriter {
	return &flakyWriter{failCount: failCount, started: make(chan struct{})}
}

var errTransientTun = errors.New("write: network is down")

func (w *flakyWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.once.Do(func() { close(w.started) })
	if w.failures < w.failCount {
		w.failures++
		return 0, errTransientTun
	}
	cp := make([]byte, len(p))
	copy(cp, p)
	w.writes = append(w.writes, cp)
	return len(p), nil
}

func (w *flakyWriter) written() [][]byte {
	w.mu.Lock()
	defer w.mu.Unlock()
	out := make([][]byte, len(w.writes))
	copy(out, w.writes)
	return out
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool) bool {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return true
		}
		time.Sleep(2 * time.Millisecond)
	}
	return cond()
}

func TestBufferedTunWriterRecoversFromTransientError(t *testing.T) {
	writer := newFlakyWriter(3)
	b := newBufferedTunWithWriter(nil, writer)
	defer b.halt()

	if _, err := b.Write([]byte("packet-1")); err != nil {
		t.Fatalf("Write must not surface an error: %v", err)
	}

	// The first packet is retried through the transient failures and delivered.
	if !waitFor(t, 3*time.Second, func() bool { return len(writer.written()) == 1 }) {
		t.Fatalf("packet was not delivered after retries (failures=%d)", writer.failures)
	}

	// The writer keeps working afterwards; it did not exit on the error.
	if _, err := b.Write([]byte("packet-2")); err != nil {
		t.Fatalf("Write after recovery: %v", err)
	}
	if !waitFor(t, 3*time.Second, func() bool { return len(writer.written()) == 2 }) {
		t.Fatal("writer stopped after a transient error")
	}
	if got := string(writer.written()[1]); got != "packet-2" {
		t.Fatalf("unexpected payload: %q", got)
	}
}

// A writer that fails for longer than the retry budget must not kill the drain
// goroutine: the packet is dropped and the next one still gets through.
func TestBufferedTunWriterSurvivesExhaustedRetryBudget(t *testing.T) {
	writer := newFlakyWriter(tunWriteRetryAttempts)
	b := newBufferedTunWithWriter(nil, writer)
	defer b.halt()

	if _, err := b.Write([]byte("lost")); err != nil {
		t.Fatalf("Write must not surface an error: %v", err)
	}
	if !waitFor(t, 5*time.Second, func() bool { return b.writeFailures.Load() == 1 }) {
		t.Fatalf("expected the first packet to be dropped after the retry budget (failures=%d)", b.writeFailures.Load())
	}

	if _, err := b.Write([]byte("recovered")); err != nil {
		t.Fatalf("Write while degraded: %v", err)
	}
	if !waitFor(t, 5*time.Second, func() bool { return len(writer.written()) == 1 }) {
		t.Fatal("writer never resumed after the failing window")
	}
	if got := string(writer.written()[0]); got != "recovered" {
		t.Fatalf("unexpected payload: %q", got)
	}
}

// While the interface is still down, packets must be dropped on a single attempt
// instead of paying the full 40-attempt backoff each: that would stall the drain
// goroutine for seconds per packet and back the queue up.
func TestBufferedTunDegradedWriterDropsWithoutFullBackoff(t *testing.T) {
	writer := newFlakyWriter(1 << 30)
	b := newBufferedTunWithWriter(nil, writer)
	defer b.halt()

	// Exhaust the retry budget once to enter the degraded state.
	if _, err := b.Write([]byte("first")); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if !waitFor(t, 5*time.Second, func() bool { return b.writeFailures.Load() >= 1 }) {
		t.Fatal("writer never entered the degraded state")
	}

	start := time.Now()
	for i := 0; i < 10; i++ {
		if _, err := b.Write([]byte("degraded")); err != nil {
			t.Fatalf("Write while degraded: %v", err)
		}
	}
	if !waitFor(t, 3*time.Second, func() bool { return b.writeFailures.Load() >= 11 }) {
		t.Fatalf("degraded writer still retried with full backoff (failures=%d)", b.writeFailures.Load())
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Fatalf("degraded drops took %v; they must not pay the full retry backoff", elapsed)
	}
}

// halt() is called from multiple shutdown paths (stop, stack teardown) and must
// be idempotent; a double close used to panic.
func TestBufferedTunHaltIsIdempotent(t *testing.T) {
	b := newBufferedTunWithWriter(nil, newFlakyWriter(0))
	b.halt()
	b.halt()
	b.halt()

	// Write after halt must stay non-blocking and error-free so gVisor's dispatch
	// loop never stalls on a stopped writer.
	done := make(chan struct{})
	go func() {
		_, _ = b.Write([]byte("post-halt"))
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Write blocked after halt")
	}
}

func TestBufferedTunWriteIsNonBlockingWhenQueueIsFull(t *testing.T) {
	// A writer that never completes: no writes are consumed, so the queue fills.
	writer := newFlakyWriter(1 << 30)
	b := newBufferedTunWithWriter(nil, writer)
	defer b.halt()

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < tunWriteQueueDepth*2; i++ {
			if _, err := b.Write([]byte("flood")); err != nil {
				t.Errorf("Write: %v", err)
				return
			}
		}
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("Write blocked once the queue filled up")
	}
	if b.dropped.Load() == 0 {
		t.Fatal("expected drops once the queue was full")
	}
}

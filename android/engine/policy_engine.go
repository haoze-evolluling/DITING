// policy_engine.go drives the Rust policy kernel: snapshot lifecycle and atomic swaps.
//
// The JSON payload is passed through untouched. The kernel decodes it, builds its tables and owns
// `filterEnabled`, normalization and the decision cache, so Go neither parses the payload nor keeps
// a second view of it.

package tunnel

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

type policyEngine struct {
	snapshot    atomic.Pointer[policySnapshot]
	initialized atomic.Bool

	// mu serialises apply/close so a swap and a shutdown cannot interleave.
	mu sync.Mutex
}

func newPolicyEngine() *policyEngine {
	pe := &policyEngine{}
	pe.snapshot.Store(&policySnapshot{})
	return pe
}

func (pe *policyEngine) isActive() bool {
	return pe != nil && pe.initialized.Load()
}

func (pe *policyEngine) hasRules() bool {
	if pe == nil {
		return false
	}
	snap := pe.snapshot.Load()
	return snap != nil && snap.hasRules
}

func (pe *policyEngine) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string) {
	if pe == nil {
		return false, ""
	}
	snap := pe.snapshot.Load()
	if snap == nil {
		return false, ""
	}
	return snap.evaluate(domain, appName, qtype)
}

// applySnapshot builds a kernel snapshot and publishes it. An error is fatal for the caller's
// start-up: the kernel is the only implementation of the walk.
func (pe *policyEngine) applySnapshot(jsonStr string) error {
	if pe == nil {
		return fmt.Errorf("policy engine is nil")
	}

	native, err := newNativePolicy(jsonStr)
	if err != nil {
		return err
	}
	snap := newPolicySnapshot(native)

	pe.mu.Lock()
	prev := pe.snapshot.Swap(snap)
	if prev != nil && prev.native != nil {
		// Pin both handles while the swap is still under the lock: a concurrent close() may release
		// the snapshot it displaces, and it must see these pins before it waits.
		snap.native.pin()
		prev.native.pin()
	}
	pe.mu.Unlock()
	pe.initialized.Store(true)
	if prev != nil && prev.native != nil {
		go func() {
			defer snap.native.unpin()
			defer prev.native.unpin()
			snap.prewarmFrom(prev)
		}()
		// The kernel keeps the DTRI mappings alive per handle; a query already inside the library
		// is not preemptible, so the release waits for it (see nativePolicy.release).
		stale := prev.native
		time.AfterFunc(2*time.Second, stale.release)
	}
	return nil
}

func (pe *policyEngine) close() {
	if pe == nil {
		return
	}
	pe.mu.Lock()
	defer pe.mu.Unlock()

	prev := pe.snapshot.Swap(&policySnapshot{})
	if prev != nil && prev.native != nil {
		prev.native.release()
	}
	pe.initialized.Store(false)
}

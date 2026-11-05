// policy_engine.go drives the Rust policy kernel: snapshot lifecycle, atomic swaps and the JSON
// payload the kernel builds its tables from.

package tunnel

import (
	"encoding/json"
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
	pe.snapshot.Store(&policySnapshot{filterEnabled: true})
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

// ruleSnapshotJSON decodes only the field the Go side keeps; everything else in the payload is the
// kernel's business.
type ruleSnapshotJSON struct {
	FilterEnabled *bool `json:"filterEnabled"`
}

// applySnapshot builds a kernel snapshot and publishes it. An error is fatal for the caller's
// start-up: the kernel is the only implementation of the walk.
func (pe *policyEngine) applySnapshot(jsonStr string) error {
	if pe == nil {
		return fmt.Errorf("policy engine is nil")
	}

	var req ruleSnapshotJSON
	if err := json.Unmarshal([]byte(jsonStr), &req); err != nil {
		return fmt.Errorf("unmarshal rule snapshot json: %w", err)
	}

	native, err := newNativePolicy(jsonStr)
	if err != nil {
		return err
	}
	snap := newPolicySnapshot(native, req.FilterEnabled)

	pe.mu.Lock()
	prev := pe.snapshot.Swap(snap)
	pe.mu.Unlock()
	pe.initialized.Store(true)
	if snap.cache != nil && prev != nil && prev.cache != nil {
		go snap.prewarmFrom(prev)
	}
	if prev != nil && prev.native != nil {
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

	prev := pe.snapshot.Swap(&policySnapshot{filterEnabled: true})
	if prev != nil && prev.native != nil {
		prev.native.release()
	}
	pe.initialized.Store(false)
}

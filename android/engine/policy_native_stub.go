//go:build !cgo

// policy_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust policy kernel is required at runtime, so this build flavour compiles but refuses every
// snapshot: `ApplyRuleSnapshot` fails, which fails the engine start. Android builds cgo (the
// shipped AAR and both .so files), so this only affects `go build`/`go vet` on a machine without a
// C compiler.

package tunnel

import "errors"

// nativePolicyABIVersion mirrors the real loader so both flavours document the same contract.
const nativePolicyABIVersion = 4

// Snapshot shape bits reported by `diting_policy_snapshot_flags`.
const (
	nativeFlagHasRules       = 1 << 0
	nativeFlagAppSensitive   = 1 << 1
	nativeFlagQtypeSensitive = 1 << 2
)

var errNativePolicyUnavailable = errors.New("native policy kernel unavailable: this build has no cgo")

// nativePolicy is never constructed without cgo; it exists so the snapshot code type-checks.
type nativePolicy struct{ flags uint32 }

func newNativePolicy(string) (*nativePolicy, error) {
	return nil, errNativePolicyUnavailable
}

func (p *nativePolicy) evaluate(string, string, uint16) (bool, string) { return false, "" }

func (p *nativePolicy) evaluateUncached(string, string, uint16) (bool, string) { return false, "" }

func (p *nativePolicy) prewarm(*nativePolicy) {}

func (p *nativePolicy) pin() {}

func (p *nativePolicy) unpin() {}

func (p *nativePolicy) release() {}

//go:build !cgo

// policy_native_stub.go keeps the engine buildable without a C toolchain: `CGO_ENABLED=0` (the
// default when no compiler is installed) simply never takes the Rust policy kernel, so every
// decision goes through the Go implementation in policy_snapshot.go.
//
// The Android AAR is built with cgo enabled, which is where the native path is used.

package tunnel

// nativePolicyABIVersion mirrors the real loader; it is unused here but keeps the constant
// documented in one place for both build flavours.
const nativePolicyABIVersion = 1

const (
	nativeFlagHasRules       = 1 << 0
	nativeFlagAppSensitive   = 1 << 1
	nativeFlagQtypeSensitive = 1 << 2
)

// nativePolicy is never constructed without cgo, but the shape has to keep policy_native_parity.go
// compiling.
type nativePolicy struct{ flags uint32 }

func newNativePolicy(string, int) (*nativePolicy, error) {
	return nil, errNativePolicyUnavailable
}

func (p *nativePolicy) evaluate(string, string, uint16) (bool, string, bool) {
	return false, "", false
}

func (p *nativePolicy) release() {}

func nativeLower(string) (string, bool) { return "", false }

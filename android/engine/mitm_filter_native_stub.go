//go:build !cgo

// mitm_filter_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust MITM filter kernel is required for interception, so this build flavour compiles but
// cannot open a filter: `NewMitmFilter` fails, `StartStackMitm` reports failure, and the tunnel
// runs without MITM. Android builds cgo (the shipped AAR and the .so files), so this only affects
// `go build`/`go vet` on a machine without a C compiler.

package tunnel

import "errors"

var errMitmFilterUnavailable = errors.New("Rust MITM filter kernel is not available without cgo")

// nativeMitmFilter is never constructed without cgo; it exists so the wrapper type-checks.
type nativeMitmFilter struct{}

func newNativeMitmFilter() (*nativeMitmFilter, error) {
	return nil, errMitmFilterUnavailable
}

func (h *nativeMitmFilter) setAllowedUIDs(string) int { return 0 }

func (h *nativeMitmFilter) isUIDAllowed(int64) bool { return false }

func (h *nativeMitmFilter) hasAllowedUIDs() bool { return false }

func (h *nativeMitmFilter) setBypassRules(string) int { return 0 }

func (h *nativeMitmFilter) allowsInterception(string, int64) bool { return false }

func (h *nativeMitmFilter) recordFailure(string, string, int64) mitmReport { return mitmReport{} }

func (h *nativeMitmFilter) blacklist(string, string, int64) (mitmReport, bool) {
	return mitmReport{}, false
}

func (h *nativeMitmFilter) clear() {}

func (h *nativeMitmFilter) remove(string) {}

func (h *nativeMitmFilter) loadPersistent(string, int64) int { return 0 }

func (h *nativeMitmFilter) blacklistCount(int64) int { return 0 }

func (h *nativeMitmFilter) free() {}

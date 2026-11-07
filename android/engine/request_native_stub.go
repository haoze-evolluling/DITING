//go:build !cgo

// request_native_stub.go keeps the engine buildable without a C toolchain.
//
// Without the Rust kernel no request rule can be normalized or matched, so the rule table is inert:
// `SetRequestRules` keeps the rules in Go (for nothing but a future kernel) and every request falls
// through to the domain-rule fallback with its raw host. Android builds cgo (the shipped AAR and the
// .so files), so this only affects `go build` / `go vet` on a machine without a C compiler.

package tunnel

import "errors"

// errRequestKernelMissing mirrors the cgo build's sentinel.
var errRequestKernelMissing = errors.New("Rust request kernel is unavailable")

// nativeRequestRules is the cgo build's handle; there is no kernel to hold one here.
type nativeRequestRules struct{}

func newNativeRequestRules(rules []requestRule) (*nativeRequestRules, error) {
	return nil, errRequestKernelMissing
}

func (r *nativeRequestRules) match(scheme, host, path string) (requestDecision, error) {
	return requestDecision{}, errRequestKernelMissing
}

func (r *nativeRequestRules) release() {}

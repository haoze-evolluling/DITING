//go:build !cgo

// dns_core_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust DNS answer kernel drives two features only: the "is this a null block" verdict on a
// forwarded answer and the dynamic block escalation. Without it an answer is logged as normal and
// every block keeps the configured response mode. Android builds cgo (the shipped AAR and the
// .so files), so this only affects `go build` / `go vet` on a machine without a C compiler. It
// never changes what is answered.

package tunnel

import "errors"

var errDNSCoreUnavailable = errors.New("Rust DNS answer kernel is not available without cgo")

func inspectNativeAnswer(payload []byte) (blocked bool, addresses string, err error) {
	return false, "", errDNSCoreUnavailable
}

func dnsCoreAvailable() bool { return false }

// nativeDynamicBlocks is the opaque kernel handle of the cgo build; nothing can open one here.
type nativeDynamicBlocks struct{}

func newNativeDynamicBlocks() (*nativeDynamicBlocks, error) {
	return nil, errDNSCoreUnavailable
}

func (h *nativeDynamicBlocks) reset() {}

func (h *nativeDynamicBlocks) response(
	domain string,
	enabled bool,
	threshold uint32,
	windowNs, nxDomainNs int64,
	fallback uint32,
	nowNs int64,
) ResponseType {
	return ResponseType(fallback)
}

func (h *nativeDynamicBlocks) free() {}

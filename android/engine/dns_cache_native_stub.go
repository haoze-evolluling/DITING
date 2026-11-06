//go:build !cgo

// dns_cache_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust DNS cache kernel is required for caching, so this build flavour compiles but refuses
// every cache write and every lookup: answers go straight to the resolver. Android builds cgo (the
// shipped AAR and the .so files), so this only affects `go build`/`go vet` on a machine without a
// C compiler. It never changes an answer, only whether it is remembered.

package tunnel

import "errors"

var errDNSCacheUnavailable = errors.New("Rust DNS cache kernel is not available without cgo")

// nativeDNSCacheHandle is the opaque cache handle of the cgo build; nothing can open one here.
type nativeDNSCacheHandle struct{}

func newNativeDNSCache(cfg dnsCacheConfig) (*nativeDNSCacheHandle, uint32, error) {
	return nil, 0, errDNSCacheUnavailable
}

func (h *nativeDNSCacheHandle) updatePolicy(cfg dnsCacheConfig) (uint32, error) {
	return 0, errDNSCacheUnavailable
}

func (h *nativeDNSCacheHandle) close() {}

func (h *nativeDNSCacheHandle) free() {}

func (h *nativeDNSCacheHandle) clear() {}

func (h *nativeDNSCacheHandle) lookup(rawQuery []byte, count bool) (*dnsCacheHit, error) {
	return nil, nil
}

func (h *nativeDNSCacheHandle) put(rawQuery, rawResponse []byte) bool { return false }

func (h *nativeDNSCacheHandle) refreshBegin(rawQuery []byte) bool { return false }

func (h *nativeDNSCacheHandle) refreshDone(rawQuery []byte) {}

func (h *nativeDNSCacheHandle) stats() (dnsCacheStats, error) {
	return dnsCacheStats{}, errDNSCacheUnavailable
}

func (h *nativeDNSCacheHandle) snapshot(limit uint32) ([]dnsCacheEntrySnapshot, error) {
	return nil, errDNSCacheUnavailable
}

// nativeQuestionKey reports "cannot cache" for every call: there is no second wire parser in Go to
// fall back to, that is what the kernel replaced.
func nativeQuestionKey(rawQuery, dst []byte) (key []byte, nameLen int, qtype, qclass uint16, ok bool) {
	return nil, 0, 0, 0, false
}

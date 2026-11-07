//go:build !cgo

// ipcache_native_stub.go keeps the engine buildable without a C toolchain.
//
// Without the Rust kernel the hostname hints are disabled (every lookup misses), which only costs
// the label of direct-IP flows. Android builds cgo (the shipped AAR and the .so files), so this
// only affects `go build` / `go vet` on a machine without a C compiler.

package tunnel

import "errors"

var errIPCacheUnavailable = errors.New("Rust ipcache kernel is not available without cgo")

// nativeIPDomainCache is the opaque kernel handle of the cgo build; nothing can open one here.
type nativeIPDomainCache struct{}

func newNativeIPDomainCache(maxSize int) (*nativeIPDomainCache, error) {
	return nil, errIPCacheUnavailable
}

func (h *nativeIPDomainCache) put(ip, domain string) {}

func (h *nativeIPDomainCache) get(ip string) string { return "" }

func (h *nativeIPDomainCache) len() int { return 0 }

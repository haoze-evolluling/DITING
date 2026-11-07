//go:build !cgo

// bootstrap_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust kernel drives bootstrap scoring and the host cache only: without it the resolver
// reports bootstrap as disabled and every encrypted provider is dialed by hostname through the
// normal path, which is the same shape as a resolver configured without bootstrap servers.
// Android builds cgo (the shipped AAR and the .so files), so this only affects `go build` /
// `go vet` on a machine without a C compiler. It never changes an answer.

package tunnel

import "errors"

var errBootstrapUnavailable = errors.New("Rust bootstrap kernel is not available without cgo")

// nativeBootstrap is the opaque kernel handle of the cgo build; nothing can open one here.
type nativeBootstrap struct{}

// planResult mirrors the cgo build's decoded plan payload.
type planResult struct {
	primary     int
	fallbacks   []int
	exploration bool
}

func newNativeBootstrap() (*nativeBootstrap, error) {
	return nil, errBootstrapUnavailable
}

func (h *nativeBootstrap) recordResult(id string, success bool, elapsedMs, nowNs int64) {}

func (h *nativeBootstrap) score(id string, entryWeight float64, nowNs int64) (float64, bool, float64, bool) {
	return 0, false, 0, false
}

func (h *nativeBootstrap) plan(ips []bootstrapIPConfig, nowNs int64, exploreRoll, weightRoll float64, indexRoll uint64) (planResult, error) {
	return planResult{primary: -1}, errBootstrapUnavailable
}

func (h *nativeBootstrap) cacheGet(host string, nowNs int64) (string, bool) { return "", false }

func (h *nativeBootstrap) cachePut(host, ip string, nowNs int64) {}

func (h *nativeBootstrap) clearCache() {}

func (h *nativeBootstrap) reset() {}

func (h *nativeBootstrap) healthCount() int { return 0 }

func (h *nativeBootstrap) free() {}

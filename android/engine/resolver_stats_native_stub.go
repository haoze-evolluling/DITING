//go:build !cgo

// resolver_stats_native_stub.go keeps the engine buildable without a C toolchain.
//
// The Rust statistics kernel drives the scheduling heuristics only: without it every provider stays
// "cold" (default score, cold hedge / attempt timeout / UDP retry, every attempt allowed), which is
// the same shape a provider that never recorded a sample already had. Android builds cgo (the
// shipped AAR and the .so files), so this only affects `go build` / `go vet` on a machine without a
// C compiler. It never changes an answer, only how eagerly providers are raced and retried.

package tunnel

import "errors"

var errResolverStatsUnavailable = errors.New("Rust resolver stats kernel is not available without cgo")

// nativeProviderStats is the opaque kernel handle of the cgo build; nothing can open one here.
type nativeProviderStats struct{}

func newNativeProviderStats() (*nativeProviderStats, error) {
	return nil, errResolverStatsUnavailable
}

func (h *nativeProviderStats) recordSuccess(rttNs, nowNs int64) {}

func (h *nativeProviderStats) recordFailure(weight uint32, nowNs int64) {}

func (h *nativeProviderStats) recordPolicyFailure(nowNs int64) {}

func (h *nativeProviderStats) allowAttempt(nowNs int64) bool { return true }

func (h *nativeProviderStats) recordCensored(elapsedNs int64) {}

func (h *nativeProviderStats) score(nowNs int64) int64 { return 0 }

func (h *nativeProviderStats) hedgeDelay() int64 { return 0 }

func (h *nativeProviderStats) attemptTimeout() int64 { return 0 }

func (h *nativeProviderStats) udpRetryDelay() int64 { return 0 }

func (h *nativeProviderStats) sampleCount() int64 { return 0 }

func (h *nativeProviderStats) failureCount() uint32 { return 0 }

func (h *nativeProviderStats) free() {}

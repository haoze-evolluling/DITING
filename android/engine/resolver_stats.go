// resolver_stats.go is the Go face of the Rust provider statistics kernel.
//
// The RTO-style estimator (SRTT + RTTVAR), the EWMA failure ratio, the time-decayed
// consecutive-failure penalty, the exponential circuit breaker and the three adaptive delays live
// in rust/diting-resolver-core (see src/stats.rs). What stays here is the Go type the resolver
// holds, the `time.Duration` / `time.Time` conversions and the values reported when the kernel is
// absent: a provider without statistics is "cold" (default score, cold hedge / attempt timeout /
// UDP retry, every attempt allowed), which is the behaviour the call sites already had for
// providers that never recorded a sample.
//
// The kernel never reads a clock: every call passes time.Now() or the caller's instant as unix
// nanoseconds, so a scripted sequence replays exactly (rust/diting-resolver-core/tests/corpus.rs).
//
// The tuning table below is the specification the kernel implements and the Go tests pin it to;
// only the four cold values are still read by this file (the no-kernel fallback).

package tunnel

import (
	"runtime"
	"time"
)

const (
	// defaultEWMA is the score of a provider with no samples: 50 ms.
	defaultEWMA = 50 * time.Millisecond

	// Hedge delay bounds for smart_prediction.
	hedgeDelayCold = 50 * time.Millisecond
	hedgeDelayMin  = 20 * time.Millisecond
	hedgeDelayMax  = 800 * time.Millisecond

	// Per-attempt timeout for primary_backup sequential failover.
	attemptTimeoutCold = 1500 * time.Millisecond

	// Plain UDP retry interval within a single upstream query.
	udpRetryDelayCold = 400 * time.Millisecond
	udpRetryDelayMin  = 200 * time.Millisecond

	// The consecutive-failure penalty halves every half life.
	failurePenaltyHalfLife = 30 * time.Second
)

// providerStats owns one kernel handle: the health model of one configured upstream.
type providerStats struct {
	native *nativeProviderStats
}

func newProviderStats() *providerStats {
	stats := &providerStats{}
	handle, err := newNativeProviderStats()
	if err != nil {
		// The loader logged the reason once per process; this provider stays cold.
		return stats
	}
	stats.native = handle
	// The handle is released with the statistics: no caller can hold the pointer after the last
	// reference to providerStats is gone, so no goroutine can touch a freed handle.
	runtime.SetFinalizer(stats, func(s *providerStats) {
		if s.native != nil {
			s.native.free()
			s.native = nil
		}
	})
	return stats
}

func (s *providerStats) RecordSuccess(rtt time.Duration) {
	if s == nil || s.native == nil {
		return
	}
	s.native.recordSuccess(int64(rtt), time.Now().UnixNano())
}

func (s *providerStats) RecordFailure() {
	if s == nil || s.native == nil {
		return
	}
	s.native.recordFailure(1, time.Now().UnixNano())
}

// RecordPolicyFailure records a policy/configuration rejection (REFUSED, FORMERR, NOTIMP) with a
// heavier weight so the circuit breaker trips faster.
func (s *providerStats) RecordPolicyFailure() {
	if s == nil || s.native == nil {
		return
	}
	s.native.recordPolicyFailure(time.Now().UnixNano())
}

// AllowAttempt reports whether the provider may be tried at `now` under circuit-breaker rules.
// When the circuit is open, requests are skipped until the cooldown expires, at which point a
// single half-open probe is allowed.
func (s *providerStats) AllowAttempt(now time.Time) bool {
	if s == nil || s.native == nil {
		return true
	}
	return s.native.allowAttempt(now.UnixNano())
}

// RecordCensored records a query that was cancelled because another provider answered first. It is
// not a failure, but the provider was at least `elapsed` slow, so it is used as a lower-bound RTT
// sample when it exceeds SRTT.
func (s *providerStats) RecordCensored(elapsed time.Duration) {
	if s == nil || s.native == nil {
		return
	}
	s.native.recordCensored(int64(elapsed))
}

func (s *providerStats) Score() time.Duration {
	return s.scoreAt(time.Now())
}

// scoreAt is the expected cost of using this provider at `now`: SRTT plus a failure-ratio cost
// plus the consecutive-failure penalty, which halves every failurePenaltyHalfLife.
func (s *providerStats) scoreAt(now time.Time) time.Duration {
	if s == nil || s.native == nil {
		return defaultEWMA
	}
	return time.Duration(s.native.score(now.UnixNano()))
}

// HedgeDelay is how long smart_prediction waits on this provider before launching the next
// candidate: roughly its tail latency (SRTT + 2*RTTVAR).
func (s *providerStats) HedgeDelay() time.Duration {
	if s == nil || s.native == nil {
		return hedgeDelayCold
	}
	return time.Duration(s.native.hedgeDelay())
}

// AttemptTimeout is the per-attempt timeout for sequential failover (SRTT + 4*RTTVAR).
func (s *providerStats) AttemptTimeout() time.Duration {
	if s == nil || s.native == nil {
		return attemptTimeoutCold
	}
	return time.Duration(s.native.attemptTimeout())
}

// UDPRetryDelay is the adaptive initial UDP read timeout before retrying a plain UDP packet on the
// same upstream (SRTT + 4*RTTVAR).
func (s *providerStats) UDPRetryDelay() time.Duration {
	if s == nil || s.native == nil {
		return udpRetryDelayCold
	}
	return time.Duration(s.native.udpRetryDelay())
}

// sampleCount is how many RTT samples were folded in; used by the white-box tests.
func (s *providerStats) sampleCount() int64 {
	if s == nil || s.native == nil {
		return 0
	}
	return s.native.sampleCount()
}

// failureCount is the consecutive-failure streak; used by the white-box tests.
func (s *providerStats) failureCount() int {
	if s == nil || s.native == nil {
		return 0
	}
	return int(s.native.failureCount())
}

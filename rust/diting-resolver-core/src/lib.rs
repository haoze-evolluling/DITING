//! The upstream provider statistics model of the Android tunnel engine.
//!
//! One [`stats::ProviderStats`] per configured DNS provider: a smoothed RTT plus smoothed mean
//! deviation (the TCP RTO estimator), an EWMA failure ratio, a time-decayed consecutive-failure
//! penalty and the exponential-backoff circuit breaker. Together they drive the provider ranking,
//! the adaptive hedge delay, the per-attempt timeout of sequential failover and the plain-UDP
//! retry interval.
//!
//! The model is the whole of `android/engine/resolver_stats.go` after migration; the Go side keeps
//! only a handle, the `time.Duration` conversions and the fallback values used when the kernel is
//! absent. Time never comes from the kernel: every stateful call takes `now_ns` (unix nanoseconds)
//! and every duration is nanoseconds, so a trace can be replayed exactly.

pub mod ffi;
pub mod stats;

pub use stats::ProviderStats;

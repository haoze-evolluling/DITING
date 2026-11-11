//! The engine's telemetry and attribution kernels.
//!
//! Three pieces of the Android tunnel engine used to keep their state in Go and they all sit on the
//! same reporting path:
//!
//! * `LogAggregator` — the bounded batch queue behind `log_aggregator.go`. It owns the 2048-slot
//!   buffer, the 3/4 high-water shed for connection logs, the two drop counters and the 50-item
//!   drains. Go keeps the flush timer, the callback and the JSON encoding of a drained batch.
//! * `TrafficTracker` — the per-UID byte counters behind `traffic_tracker.go`: `record` adds to the
//!   delta and total atomics, `tick` swaps the deltas out. Go keeps the ticker goroutine, the
//!   `net.Conn` wrapper and the JSON encoding of a tick.
//! * `FlowUidCache` / `UidPackageCache` — the two TTL caches behind `uid_cache.go`. Go keeps the
//!   JNI-backed inner resolver; the TTLs, the 1024 / 256 entry caps and the prune-vs-reset behaviour
//!   live here, with the clock injected (`now_ns`) so expiry is testable without sleeping.
//!
//! None of these kernels changes a DNS answer. When a library is missing the engine degrades the
//! same way it did before the kernel existed: logs are still delivered (unbatched), flows lose their
//! byte accounting and attribution lookups always miss (each one goes to JNI).

pub mod ffi;
pub mod logagg;
pub mod payload;
pub mod traffic;
pub mod uidcache;

pub use logagg::{LogAggregator, LogItem, PushOutcome};
pub use traffic::{Delta, TrafficTracker};
pub use uidcache::{FlowKey, FlowUidCache, UidPackageCache};

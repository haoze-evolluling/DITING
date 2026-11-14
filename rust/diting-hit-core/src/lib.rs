//! Rule-hit counters: a sharded, low-overhead tally keyed by `(rule_id, list_id)`.
//!
//! The engine increments on every rule match; the UI periodically asks for a snapshot and flushes
//! it to SQLite. Splitting the map across shards keeps concurrent increments from contending on one
//! lock, and every shard is a plain `Mutex<HashMap>` — the counters must never be the reason a
//! packet is dropped, so a poisoned lock is recovered rather than propagated.
//!
//! Layout:
//! * [`counters`] — the [`counters::HitCounters`] sharded tally and its snapshot.
//! * [`ffi`] — the C ABI surface for a `dart:ffi` / JNI caller.

pub mod counters;
pub mod ffi;

pub use counters::{HitCounters, HitEntry};
pub use ffi::ABI_VERSION;

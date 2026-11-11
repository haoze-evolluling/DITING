//! The encrypted-DNS bootstrap scoring kernel of the Android tunnel engine.
//!
//! Bootstrap resolution asks several public DNS servers for the address of an encrypted provider's
//! hostname and then races them. This kernel owns what the Go engine used to keep in
//! `bootstrapIPHealth` / `bootstrapResolver.choosePlan`:
//!
//! * a per-endpoint health model with exponential half-life decay, EWMA latency and jitter,
//!   a consecutive-failure penalty, and a 30 s cooldown after three failures in a row;
//! * the weighted primary pick with an exploration rate that rises while endpoints are cooling
//!   down or under-sampled, plus the fallback order (weight descending, stable);
//! * the one-minute host → address cache that a config change clears.
//!
//! Everything time-related is injected: every call takes `now_ns` (unix nanoseconds), so the
//! model can be replayed exactly (see `tests/fixtures/health_trace.tsv`, produced by the old Go
//! implementation). The two random choices are injected as well: Go passes
//! `rand.Float64()` for the exploration roll and the weighted roll, and `rand.Uint64()` for the
//! exploration pick, which the kernel reduces modulo the candidate count. Only that reduction
//! differs from `rand.Intn` (modulo bias below 2^-40 for any realistic count).
//!
//! The kernel never dials, never logs and never reads a clock. Go keeps the JSON config, the UDP
//! query itself, the logging callback and the "kernel absent" fallback.

pub mod engine;
pub mod ffi;
pub mod health;
pub mod payload;

pub use engine::{BootstrapKernel, Plan};
pub use health::{Health, Score};

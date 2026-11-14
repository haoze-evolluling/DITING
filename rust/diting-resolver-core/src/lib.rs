//! The upstream provider statistics and the query scheduler of the Android tunnel engine.
//!
//! One [`stats::ProviderStats`] per configured DNS provider: a smoothed RTT plus smoothed mean
//! deviation (the TCP RTO estimator), an EWMA failure ratio, a time-decayed consecutive-failure
//! penalty and the exponential-backoff circuit breaker. Together they drive the provider ranking,
//! the adaptive hedge delay, the per-attempt timeout of sequential failover and the plain-UDP
//! retry interval.
//!
//! [`schedule::Schedule`] turns those readings into the query's plan: the four strategies'
//! attempt order, the clipped per-attempt budgets, the staggered hedge, the encrypted-upstream
//! grace window and the closing race-log event. Go keeps the goroutines, the contexts, the timers
//! and the sockets.
//!
//! Time never comes from the kernel: every stateful call takes `now_ns` / `elapsed_ns` (unix
//! nanoseconds) and every duration is nanoseconds, so a trace can be replayed exactly.

pub mod ffi;
pub mod payload;
pub mod policy_group;
pub mod schedule;
pub mod stats;

pub use policy_group::{select, GroupType, MemberReading, PolicyGroup, Selection};
pub use schedule::{Event, Hedge, Launch, Outcome, PlanInput, Provider, Schedule, Step, Strategy};
pub use stats::ProviderStats;

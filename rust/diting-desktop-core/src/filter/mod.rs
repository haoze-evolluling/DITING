//! Desktop rule/filter engine (the former Go service's `internal/core/rule_engine*.go`).
//!
//! The facade keeps what Go kept outside the Rust kernels: configuration ownership, subscription
//! cache management, pause and weekly schedules, client-group rule selection, statistics and the
//! service-level policy that turns a matcher verdict into a [`CheckHostResult`]. Which rule answers
//! a query lives in `diting-filter-core`; rewrite values come from `diting-rewrite-core`; response
//! alias chains are planned by `diting-response-core`; service selections expand through
//! `diting-services-core`.
//!
//! Index rebuilds are published as one `MatcherSnapshot` swap. Fetching and CPU-bound rebuilds run
//! through `tokio::spawn_blocking`, so the DNS hot path never parses a rule file.
//!
//! Layout:
//! * [`types`] — result/stat/API types and reason codes.
//! * `engine` — [`RuleEngine`] and the runtime state (config, pause, groups, refresh).
//! * `ruleset` — rule parsing, source selection and the compiled matcher.
//! * `schedule` — weekly window compilation and evaluation.
//! * `bogus` — bogus-NXDOMAIN address matching.
//! * `fetch` — conditional subscription fetch and atomic cache writes.

pub mod types;

mod bogus;
mod engine;
mod fetch;
mod lists;
mod ruleset;
mod schedule;
mod state;

pub use engine::{
    extract_response_check_names, normalize_domain, now_ms, RuleEngine, MAX_RESPONSE_ALIAS_DEPTH,
};
pub use types::*;

#[cfg(test)]
mod tests;

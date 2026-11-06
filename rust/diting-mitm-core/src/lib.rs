//! MITM smart-filter kernel for the Android tunnel engine (`android/engine`).
//!
//! This crate owns `mitm_filter.go`: the per-UID allow list, the `path.Match` host patterns that
//! bypass interception, the "sensitive host" heuristics that keep banking and identity endpoints
//! out of the MITM path, the automatic blacklist with its failure streak counters, and the
//! persistent blacklist file. The Go side keeps the connection plumbing, the log lines and the
//! lifecycle of the handle; every decision is made here.
//!
//! Layout:
//! * [`pattern`] — a byte-for-byte port of Go's `path.Match` plus `matchHostPattern`.
//! * [`sensitive`] — `isSensitiveHost` / `isIPAddress`.
//! * [`filter`] — the filter state: allowed UIDs, bypass patterns, blacklist and failure streaks.
//! * [`payload`] — the binary layouts shared with `mitm_filter_native*.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! Time is injected: every stateful call takes `now_ms`, so the kernel has no clock of its own and
//! the tests pin expiry and failure-window behaviour exactly. The Go side passes
//! `time.Now().UnixMilli()`; the persistent file stores unix seconds, exactly like before.
//!
//! The library is required for MITM to start: a missing library fails `NewMitmFilter`, which fails
//! `StartStackMitm`. There is no second implementation in Go to fall back to — a silent one would
//! only hide the difference until it let a banking endpoint through the interception path.

pub mod ffi;
pub mod filter;
pub mod pattern;
pub mod payload;
pub mod sensitive;

#[cfg(test)]
mod fixture;

pub use ffi::ABI_VERSION;
pub use filter::{
    BlacklistReport, FailureReport, Filter, DEFAULT_BLACKLIST_TTL_MS, FAILURE_WINDOW_MS,
};
pub use pattern::{match_host_pattern, path_match, BadPattern};
pub use sensitive::{is_ip_address, is_sensitive_host, SENSITIVE_KEYWORDS};

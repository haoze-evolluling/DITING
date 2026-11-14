//! The upstream DNS transport kernel of the Android tunnel engine.
//!
//! `resolver_plain.go` / `resolver_dot.go` / `resolver_doh.go` / `resolver_doq.go` were mostly
//! sockets. What is not a socket lives here:
//!
//! * [`tuning`] — every transport constant the four protocols share: the query / connect / probe
//!   timeouts, the plain-UDP retry shape, the DoT idle pool bounds, the read cap, the DoH transport
//!   pool and the encrypted-upstream grace window. Go reads them once and no longer holds the table.
//! * [`endpoint`] — the `net.SplitHostPort` target split with the per-protocol default port (53 for
//!   PLAIN/TCP, 853 for DoT), and the `net.JoinHostPort` dial address with the bootstrap override.
//! * [`framing`] — the 2-byte length-prefix codec shared by TCP, DoT and DoQ, the DoT response-length
//!   validity rules, the DoQ prefix-strip rule, UDP truncation detection and the plain-UDP retry
//!   deadline arithmetic.
//! * [`doh`] — the DoH status classification (200 / 403 / other) and the one-shot retry after an
//!   `EOF`.
//! * [`pool`] — the DoT idle pool: LIFO reuse, the 15 s idle window and four connections per host.
//!   The connections themselves stay in Go (they are `*tls.Conn` values); the kernel only tracks the
//!   ids and their last-used stamps.
//! * [`plan`] — the provider-mode dispatch table (`single` / `primary_backup` / `parallel_race` /
//!   `smart_prediction` with their aliases) and the rcode policy-rejection set.
//!
//! Dialing, TLS, QUIC and `net/http` stay in Go, as do every error text and all goroutines. The
//! kernel is required for resolution: without the library a query fails instead of running on a
//! second, quieter implementation, exactly like the DNS answer kernel.

pub mod doh;
pub mod alt_svc;
pub mod endpoint;
pub mod ffi;
pub mod framing;
pub mod payload;
pub mod plan;
pub mod pool;
pub mod tuning;

pub use doh::{should_retry, status_kind, StatusKind};
pub use endpoint::{dial_address, split_target, TargetProtocol};
pub use framing::{
    doq_skip, dot_response_length, encode_length_prefixed, is_truncated, tcp_response_length,
    DotLength,
};
pub use plan::{is_policy_rejection, strategy, Strategy};
pub use pool::{Acquired, DotPool};
pub use tuning::{Tuning, TUNING};

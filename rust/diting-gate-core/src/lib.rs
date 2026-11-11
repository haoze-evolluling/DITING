//! The flow gate of the Android tunnel engine: blocked UIDs, IP classification, the outbound
//! proxy scope and the per-flow admission plan.
//!
//! Everything here used to be spread over `engine_full_tunnel.go`, `mitm_handler.go`,
//! `mitm_common.go`, `mitm_passthrough.go`, `flow_outbound.go` and `engine_outbound_scope.go`:
//!
//! * [`blocked`] - `SetBlockedUIDs`: the CSV split, `strconv.Atoi` semantics and the `uid > 0`
//!   filter, plus the membership test.
//! * [`ipclass`] - `isLoopbackOrInternal` / `isPrivateIP` and the `net.IP` predicates they were
//!   built from (loopback, unspecified, link-local unicast, RFC 1918), over raw address bytes.
//! * [`route`] - the outbound proxy scope: `perApp` (`enabled && scope == "apps"`) and
//!   `proxiesUID` (the selected-UID set, with unknown owners staying direct).
//! * [`admit`] - the three data-plane entry points' gate order (`full tunnel UDP`,
//!   `full tunnel TCP`, `MITM TCP`), returned as one action plus the "log the connection first"
//!   bit so Go keeps exactly the old log points.
//!
//! Go keeps every socket, goroutine, the peek/classify/relay work and the `net/http` / TLS
//! objects. The kernel decides only "may this flow proceed, and how".

pub mod admit;
pub mod blocked;
pub mod ffi;
pub mod ipclass;
pub mod route;

pub use admit::{admit, Decision, FlowInput};
pub use blocked::BlockedUids;
pub use route::{per_app, proxies_uid, resolver_uses_proxy};

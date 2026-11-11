//! The DNS answer inspection and block escalation of the Android tunnel engine.
//!
//! Two pieces of `android/engine` live here:
//!
//! * [`answer`] - the answer inspection every forwarding path runs on a fresh upstream reply:
//!   "is this a null block" (`isUpstreamBlockedMsg`: every A/AAAA in the answer is `0.0.0.0` /
//!   `::` / loopback) and "which addresses do we log" (`resolvedAddressesMsg`: unique in order,
//!   comma separated).
//! * [`message`] - DNS wire parsing: query info, upstream response validation and the answer
//!   extraction (`parseDNSQuery`, `validateDNSResponseParsed`, and the `dns.Msg` walk that fed
//!   the null-block verdict, the chain targets, the allowlist grants and the diagnostics reply).
//! * [`block`] - the dynamic block escalation (`dynamicBlockTracker`): per-domain request counter
//!   with a window, an NXDOMAIN hold, and NODATA for everything below the threshold.
//! * [`reply`] - the synthesized DNS answers (`standaloneBlock`, `standaloneRewrite`, the local
//!   asset host, DDR and the SERVFAIL path): the rcode, the RA bit and the answer records Go
//!   used to assemble with `dns.Msg` / `dns.NewRR`.
//! * [`rewrite_table`] - the per-domain rewrite table (`SetRewriteRules` / `rewriteLookup`):
//!   target classification (through `diting-config-core`), normalized keys and the suffix walk.
//!
//! Time is injected (`now_ns`); Go converts `time.Duration` / `time.Time` on its side. The Go enum
//! that names the four response modes stays in `dns_packet.go`: it is the enum's textual spelling
//! (one switch), not logic, and the kernel only ever echoes the numbers back.

pub mod answer;
pub mod block;
pub mod ffi;
pub mod message;
pub mod payload;
pub mod reply;
pub mod rewrite_table;

pub use answer::{inspect, AnswerEntry, Inspection};
pub use block::{BlockConfig, DynamicBlocks};
pub use message::{extract, query_info, validate, AddressRecord, Extracted, QueryInfo, Validation};
pub use reply::{ReplyPlan, ReplyRecord};
pub use rewrite_table::RewriteTable;

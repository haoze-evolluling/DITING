//! The DNS answer inspection and block escalation of the Android tunnel engine.
//!
//! Two pieces of `android/engine` live here:
//!
//! * [`answer`] - the answer inspection every forwarding path runs on a fresh upstream reply:
//!   "is this a null block" (`isUpstreamBlockedMsg`: every A/AAAA in the answer is `0.0.0.0` /
//!   `::` / loopback) and "which addresses do we log" (`resolvedAddressesMsg`: unique in order,
//!   comma separated).
//! * [`block`] - the dynamic block escalation (`dynamicBlockTracker`): per-domain request counter
//!   with a window, an NXDOMAIN hold, and NODATA for everything below the threshold.
//!
//! Time is injected (`now_ns`); Go converts `time.Duration` / `time.Time` on its side. The Go enum
//! that names the four response modes stays in `dns_packet.go`: it is the enum's textual spelling
//! (one switch), not logic, and the kernel only ever echoes the numbers back.

pub mod answer;
pub mod block;
pub mod ffi;
pub mod payload;

pub use answer::{inspect, AnswerEntry, Inspection};
pub use block::{BlockConfig, DynamicBlocks};

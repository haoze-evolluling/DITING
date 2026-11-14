//! Captive-portal detection evaluator (N6 / K6).
//!
//! Hotel / airport Wi-Fi blocks the internet until a portal login finishes. If the tunnel keeps
//! blocking during that window the user only sees "no internet"; the fix is to *notice* the portal,
//! temporarily pass the portal's domains, and prompt the login. This crate owns the judgement:
//!
//! * parse the RFC 8910 `Captive-Portal` DHCP/RA option into a URL;
//! * judge a `generate_204` probe (status code + redirect + body) into open / portal / unknown;
//! * combine the platform's `NET_CAPABILITY_CAPTIVE_PORTAL` / `NET_CAPABILITY_VALIDATED` bits with
//!   the probe to decide whether to suspend blocking.
//!
//! No I/O and no clock: the probe results arrive normalized from Kotlin/Dart, so the same portal
//! state drives both the banner and the engine's temporary bypass.
//!
//! Layout:
//! * [`evaluate`] — the pure probe/gate judgement and its unit tests.
//! * [`ffi`] — the C ABI (`magic "DCP1" | abi` header) a `dart:ffi` caller loads.

pub mod evaluate;
pub mod ffi;

pub use evaluate::{
    evaluate, gate, parse_portal_url, GateDecision, PortalState, Probe, PortalVerdict,
};
pub use ffi::ABI_VERSION;

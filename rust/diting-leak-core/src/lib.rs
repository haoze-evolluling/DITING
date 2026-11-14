//! DNS-leak detection evaluator (N6 / K6).
//!
//! A fingerprint query (`whoami.cloudflare`, `o-o.myaddr.l.google.com`, …) tells the device which
//! resolver actually answered; the tunnel's own counters tell whether a plaintext 53/853 query left
//! un-proxied. This crate owns the *judgement* — is the observed exit the one the configured
//! upstream should report, and did anything bypass it — and nothing else. Kotlin/Dart do the actual
//! probe and hand this crate a normalized [`evaluate::Probe`], so the "pass / leak / unknown"
//! verdict is one implementation the UI and the health score share.
//!
//! Layout:
//! * [`evaluate`] — the [`evaluate::Probe`] → [`evaluate::Verdict`] judgement and its unit tests.
//! * [`ffi`] — the C ABI (`magic "DLK1" | abi` header) a `dart:ffi` caller loads.
//!
//! Only ever a hint, never a hard block: fingerprint domains depend on third-party availability and
//! dual-stack / multi-upstream setups make "consistency" genuinely ambiguous (see research D1).

pub mod evaluate;
pub mod ffi;

pub use evaluate::{evaluate, LeakStatus, Probe, Verdict};
pub use ffi::ABI_VERSION;

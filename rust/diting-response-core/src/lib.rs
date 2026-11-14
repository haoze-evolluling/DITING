//! Response-side alias-chain recheck planner (R8 / K8).
//!
//! A query can resolve fine — `safe.example` — while its CNAME points at a blocked domain. The
//! engine already re-evaluates each `ChainTarget` from the answer, but the chain is attacker
//! controlled: it can be arbitrarily long or loop. This crate owns the *plan*: turn the flat,
//! ordered target list from the answer into the bounded, de-duplicated set of domains to re-check,
//! with cycle detection. Depth is capped at [`DEFAULT_MAX_DEPTH`] (8), matching the design.
//!
//! Layout:
//! * [`chain`] — [`chain::plan`] and its unit tests.
//! * [`ffi`] — the C ABI (`magic "DRC1" | abi` header) a `dart:ffi` caller loads.

pub mod chain;
pub mod ffi;

pub use chain::{plan, RecheckPlan, DEFAULT_MAX_DEPTH};
pub use ffi::ABI_VERSION;

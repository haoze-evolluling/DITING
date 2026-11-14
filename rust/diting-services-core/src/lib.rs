//! The built-in blocked-service catalog (R7 / K8).
//!
//! "Block social media for an hour" / "no video during work" needs a service directory the user can
//! pick from without typing domains. This crate owns that directory and the *pure* expansion from
//! the selected service ids to the rule patterns a blocking group is built from. It never touches
//! the database, the clock or the network: the UI shows [`catalog`] and stores the expansion
//! [`expand`] returns, so the preset list and the generated rules can never drift apart.
//!
//! Layout:
//! * [`catalog`] — the static service table and its JSON view.
//! * [`expand`] — selected service ids → rule patterns, plus its unit tests.
//! * [`ffi`] — the C ABI (`magic "DSV1" | abi` header) a `dart:ffi` caller loads.

pub mod catalog;
pub mod expand;
pub mod ffi;

pub use catalog::{Service, CATALOG};
pub use expand::expand;
pub use ffi::ABI_VERSION;

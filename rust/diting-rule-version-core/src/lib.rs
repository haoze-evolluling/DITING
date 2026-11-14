//! Subscription rule-version governance (R6 / K8).
//!
//! A subscription update can be a poisoned or accidental one; the way back is to keep the last few
//! rule-set versions and let the user diff + roll back. This crate owns the two pure decisions:
//! what changed between two rule sets, and which versions to keep. The database, the download and
//! the hash of each snapshot stay in Dart/Kotlin — but the diff and the retention policy are one
//! implementation so the preview and the stored history can never disagree.
//!
//! Layout:
//! * [`version`] — [`version::VersionEntry`], [`version::RuleDiff`], [`version::diff`] and
//!   [`version::record`], with unit tests.
//! * [`ffi`] — the C ABI (`magic "DRV1" | abi` header) a `dart:ffi` caller loads.

pub mod ffi;
pub mod version;

pub use ffi::ABI_VERSION;
pub use version::{diff, record, RuleDiff, VersionEntry, DEFAULT_MAX_VERSIONS};

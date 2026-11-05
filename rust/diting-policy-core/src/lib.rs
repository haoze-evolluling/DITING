//! Rust policy kernel for the Go tunnel engine.
//!
//! The Go engine (`android/engine`) keeps the network stack, the resolver, the cache and the
//! snapshot lifecycle, but no longer decides *which rule matches a query*: this crate owns the
//! rule tables, the wildcard index, the `.dtri` subscription trie lookup and the seven-level
//! priority walk. Go still builds the same tables for its own fallback and for the parity tests,
//! and it cross-checks both engines on every snapshot apply, so the native path can never make the
//! engine answer differently - if anything disagrees, that snapshot stays on the Go code.
//!
//! Layout:
//! * [`json`] - the snapshot payload, field for field with `ruleSnapshotJSON`.
//! * [`text`] - Go-compatible `strings.ToLower` / `TrimSpace` / suffix matching.
//! * [`dns_type`] - `dns.StringToType`, the table `dnsType` modifiers are resolved against.
//! * [`glob`] - `newWildcardMatcher`: `(?i)^glob$` compiled like `regexp.QuoteMeta`.
//! * [`wildcard_index`] - `policy_wildcard_index.go`, the same first-match-in-order index.
//! * [`dtri_read`] - `policy_dtri_reader.go`: bloom prefilter + label walk over an mmap.
//! * [`regex_go`] - Go regexp -> Rust regex translation for user regex rules.
//! * [`special`] - `specialRule` (app scope, denyallow, dnsType, regex/glob body).
//! * [`tables`] - the buckets, inverted rules and domain-or-suffix helpers of a snapshot.
//! * [`decision`] - the `(blocked, reason)` verdict, reason borrowed from the snapshot.
//! * [`snapshot`] - `policySnapshot`: tables, `hasRules`, and the priority walk.
//! * [`ffi`] - the C ABI [`ffi::ABI_VERSION`] the Go loader validates.

pub mod decision;
pub mod dns_type;
pub mod dtri_read;
pub mod ffi;
pub mod glob;
pub mod json;
pub mod regex_go;
pub mod snapshot;
pub mod special;
pub mod tables;
pub mod text;
pub mod wildcard_index;

pub use decision::Decision;
pub use ffi::ABI_VERSION;
pub use snapshot::Snapshot;

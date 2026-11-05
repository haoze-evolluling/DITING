//! Rust policy kernel for the Go tunnel engine.
//!
//! The Go engine (`android/engine`) keeps the network stack, the resolver, the cache and the
//! snapshot lifecycle, but no longer decides *which rule matches a query*: this crate owns the
//! rule tables, the wildcard index, the `.dtri` subscription trie lookup and the seven-level
//! priority walk. Go keeps no copy of the tables and no second walk: this crate is the only
//! implementation, and a snapshot it cannot build is an engine start failure.
//!
//! Layout:
//! * [`json`] - the snapshot payload `ApplyRuleSnapshot` receives from Dart.
//! * [`text`] - Go-compatible `strings.ToLower` / `TrimSpace` / suffix matching.
//! * [`dns_type`] - `dns.StringToType`, the table `dnsType` modifiers are resolved against.
//! * [`glob`] - `newWildcardMatcher`: `(?i)^glob$` compiled like `regexp.QuoteMeta`.
//! * [`wildcard_index`] - the first-match-in-order wildcard index.
//! * [`dtri_read`] - bloom prefilter + label walk over an mmap.
//! * [`regex_go`] - Go regexp -> Rust regex translation for user regex rules.
//! * [`special`] - `specialRule` (app scope, denyallow, dnsType, regex/glob body).
//! * [`tables`] - the buckets, inverted rules and domain-or-suffix helpers of a snapshot.
//! * [`decision`] - the `(blocked, reason)` verdict, reason borrowed from the snapshot.
//! * [`snapshot`] - the tables, `hasRules`, and the priority walk.
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

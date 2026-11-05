//! Rust policy kernel for the Go tunnel engine.
//!
//! The Go engine (`android/engine`) keeps the network stack, the resolver, the DNS cache and the
//! snapshot lifecycle, but no longer decides *which rule matches a query* nor remembers recent
//! answers: this crate owns the rule tables, the wildcard index, the `.dtri` subscription trie
//! lookup, the seven-level priority walk, the domain normalization and the per-snapshot decision
//! cache. Go keeps no copy of the tables, no second walk and no second cache: this crate is the only
//! implementation, and a snapshot it cannot build is an engine start failure.
//!
//! Layout:
//! * [`json`] - the snapshot payload `ApplyRuleSnapshot` receives from Dart.
//! * [`text`] - Go-compatible `strings.ToLower` / `TrimSpace` / `normalizePolicyDomain` helpers.
//! * [`dns_type`] - `dns.StringToType`, the table `dnsType` modifiers are resolved against.
//! * [`glob`] - `newWildcardMatcher`: `(?i)^glob$` compiled like `regexp.QuoteMeta`.
//! * [`wildcard_index`] - the first-match-in-order wildcard index.
//! * [`dtri_read`] - bloom prefilter + label walk over an mmap.
//! * [`regex_go`] - Go regexp -> Rust regex translation for user regex rules.
//! * [`special`] - `specialRule` (app scope, denyallow, dnsType, regex/glob body).
//! * [`tables`] - the buckets, inverted rules and domain-or-suffix helpers of a snapshot.
//! * [`decision`] - the raw `(blocked, reason)` verdict, reason borrowed from the snapshot.
//! * [`cache`] - the sharded CLOCK decision cache and its reason pool.
//! * [`snapshot`] - the tables, `hasRules`, the priority walk, `answer` and prewarming.
//! * [`ffi`] - the C ABI [`ffi::ABI_VERSION`] the Go loader validates.

pub mod cache;
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

pub use cache::Reason;
pub use decision::Decision;
pub use ffi::ABI_VERSION;
pub use snapshot::{Answer, Snapshot};

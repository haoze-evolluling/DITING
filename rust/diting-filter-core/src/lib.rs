//! Rule index and matcher for the desktop service's filter engine.
//!
//! The Go engine (`desktop/service/internal/core/rule_engine*.go`) keeps configuration, rule
//! loading, scheduling, pause, statistics and the DNS record construction for `$dnsrewrite`; this
//! crate owns *which rule answers a query*: the reversed-label tries, the wildcard/regex lists, the
//! bloom prefilter, the `$denyallow=`/`$to=` exclusions and the rewrite selection. Go keeps no
//! second copy of the index and no second priority walk, and an index it cannot build is a rule
//! engine failure rather than a silent "no rule matched".
//!
//! Boundary contract, the same one `diting-policy-core` uses: the domain arrives already
//! lowercased, trimmed and without its trailing dot (Go's
//! `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(d)), ".")`), because Go needs that value
//! anyway to build rewrite records.
//!
//! Layout:
//! * [`parse`] - rule text parsing (`rule_parser.go` moved here): lines and hosts forms in, a
//!   normalized pattern plus its flags out.
//! * [`rule`] - one parsed rule as Go hands it over: pattern, flags, `$dnstype`, exclusions and the
//!   `$dnsrewrite` fields the matcher needs to rank answers.
//! * [`trie`] - `DomainTrie`: the reversed-label trie and its suffix/exact walk.
//! * [`bloom`] - `DomainBloomFilter`: the prefilter in front of the block trie.
//! * [`index`] - `FilterIndex`: the four tiers, the rewrite buckets and [`index::FilterIndex::match_domain`].
//! * [`payload`] - the compact binary layout shared with `ffi`.
//! * [`parse_payload`] - the request/reply layout of the parser entry points.
//! * [`ffi`] - the C ABI, whose [`ffi::ABI_VERSION`] the Go loader validates.

pub mod bloom;
pub mod ffi;
pub mod index;
pub mod parse;
pub mod parse_payload;
pub mod payload;
pub mod rule;
pub mod trie;

pub use ffi::ABI_VERSION;
pub use index::{Action, Decision, FilterIndex, Reason, RewriteAnswer};
pub use rule::Rule;

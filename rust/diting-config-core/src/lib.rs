//! The configuration kernel of the Android tunnel engine.
//!
//! Everything Android pushes in as a settings payload — the DNS config (`ApplyDNSConfig`), the
//! protocol / block-response names (`SetDNS`, `SetBlockResponseType`), the DoQ endpoint form and the
//! per-domain rewrite table (`SetRewriteRules`) — used to be normalized and validated by hand in
//! `android/engine/{dns_config,dns_packet,resolver,resolver_doq,engine_config}.go`. The rules and,
//! more importantly, the exact error texts moved here so the two sides cannot disagree:
//!
//! * [`mode`] — `canonicalDNSMode`: the four scheduling modes and their aliases.
//! * [`dynamic`] — the dynamic-block defaults (5 requests / 60 s / 300 s).
//! * [`protocol`] — `ParseProtocol` and `ParseResponseType`: the two name tables.
//! * [`endpoint`] — `validateDNSProvider` (PLAIN / DOT host:port, DoH and DoQ URLs) and
//!   `parseDoQURL`.
//! * [`rewrite`] — `parseRewriteEntry` (target classification, first-one-wins) and the
//!   `TrimSuffix(ToLower(TrimSpace(domain)), ".")` normalization every lookup key goes through.
//! * [`quote`] — `fmt.Sprintf("%q")`, the shape of every error text.
//! * [`dns_config`] — one call that normalizes a whole DNS config and reports the first error in
//!   the order the old code checked them.
//!
//! Go keeps `encoding/json` (the payload shape and its decode errors are the standard library's),
//! the `Engine` state, the resolver / cache hand-off and every log line. The kernel is stateless and
//! reads no clock: it turns one config value into its normalized form, or into the error text the
//! UI shows. A missing library is a hard failure — an unvalidated config must not be applied.

pub mod dns_config;
pub mod dynamic;
pub mod endpoint;
pub mod ffi;
pub mod mode;
pub mod payload;
pub mod protocol;
pub mod quote;
pub mod rewrite;

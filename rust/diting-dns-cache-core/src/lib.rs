//! DNS cache wire kernel for the Android tunnel engine (`android/engine`).
//!
//! This is the only implementation left of the cache's wire layer: the query key
//! (`appendQuestionKey` / `parseKeyQuestion` / `cacheKey`), the response metadata
//! (`extractMinTTL`, `extractTtlOffsetsFromWire`, `extractChainTargetsFromMsg`,
//! `extractIPsFromMsg`) and the TTL/ID patching (`patchWireResponse`). Go keeps the
//! sharded LRU container, the TTL policy arithmetic, the single-flight group and the
//! background sweeper; it hands raw wire bytes to this crate and stores what comes back.
//!
//! Parsing from the wire instead of a `dns.Msg` means the cache no longer unpacks a
//! response twice: once for the resolver's validation and once for the cache. The
//! metadata below is everything `putMsg` used to read off the unpacked message.
//!
//! Layout:
//! * [`wire`] — key building, name decoding (Go `UnpackDomainName` escaping), record
//!   walk, TTL offsets, minimum TTL / SOA fallback, CNAME/SVCB/HTTPS targets, A/AAAA
//!   presentation strings, and the ID/TTL patch.
//! * [`payload`] — the binary layout shared with `dns_cache_native.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! The library is required for the cache to do anything: without it `put` refuses to
//! store an answer and every lookup misses, so the engine keeps serving directly from
//! upstream. There is no second parser in Go to fall back to, by design: two of them
//! would drift silently and cache answers with the old TTL/ID semantics.

pub mod ffi;
pub mod payload;
pub mod wire;

pub use ffi::ABI_VERSION;
pub use wire::{
    parse_response, patch_response, question_key, ChainKind, ChainTarget, QuestionKey, ResponseMeta,
};

//! DNS cache kernel for the Android tunnel engine (`android/engine`).
//!
//! This crate owns the whole cache: the wire layer (query key, response metadata, ID/TTL
//! patching), the sharded container with its LRU and deadlines, the TTL policy, the background
//! sweeper and the JSON-facing snapshot projection. The Go side only keeps the single-flight
//! coalescer around the resolver callback and the JSON marshalling of the projection.
//!
//! Parsing from the wire instead of a `dns.Msg` means the cache no longer unpacks a response
//! twice: once for the resolver's validation and once for the cache. The metadata
//! [`wire::parse_response`] reports is everything `putMsg` used to read off the unpacked message.
//!
//! Layout:
//! * [`wire`] — key building, name decoding (Go `UnpackDomainName` escaping), record
//!   walk, TTL offsets, minimum TTL / SOA fallback, CNAME/SVCB/HTTPS targets, A/AAAA
//!   presentation strings, and the ID/TTL patch.
//! * [`policy`] — configuration normalization and the TTL arithmetic.
//! * [`cache`] — shards, entries, LRU tickets, deadlines, sweeper, counters and snapshot.
//! * [`payload`] — the binary layouts shared with `dns_cache_native*.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! The library is required for the cache to do anything: without it nothing is stored and every
//! lookup misses, so the engine keeps serving directly from upstream. There is no second cache in
//! Go to fall back to, by design: two of them would drift silently and serve answers with the old
//! TTL/ID semantics.

pub mod cache;
pub mod ffi;
pub mod payload;
pub mod policy;
pub mod wire;

pub use cache::{Cache, Hit, SnapshotEntry, Stats};
pub use ffi::ABI_VERSION;
pub use policy::{Config, TtlMode};
pub use wire::{question_key, ChainKind, ChainTarget, QuestionKey, ResponseMeta};

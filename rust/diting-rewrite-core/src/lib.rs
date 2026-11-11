//! Rewrite kernel for the desktop service (`desktop/service/internal/core`).
//!
//! Two things live here:
//!
//! * [`record`] is the only implementation left of `buildRewriteRR`: the supported record types, the
//!   value grammar for every one of them, the SVCB parameter list and the target-domain check.
//! * [`action`] parses `$dnsrewrite` values into those records (or into a bare/rcode-only action)
//!   and normalizes the key cancelling exceptions are compared by.
//! * [`engine`] is the rewrite engine (`rewrite.go` + `rewrite_lookup.go`): rule indexes, PTR map,
//!   rcode overrides, the CNAME chase and owner merging. Go keeps the configuration and rebuilds a
//!   snapshot when it changes.
//!
//! `internal/core/rewrite_native.go` and `rewrite_engine_native.go` load the library at runtime
//! (pure Go `dlopen`, no cgo), check [`ffi::ABI_VERSION`] and drive it through the C ABI. A missing
//! artifact, a stale ABI or a rejected payload fails the build — there is no second implementation
//! to fall back to, by design.
//!
//! The `dns.RR` itself is still built in Go, because the answer goes straight into a `dns.Msg`:
//! the reply carries the numeric record type plus its unpacked fields.
//!
//! Layout:
//! * [`record`] — the type tables, the record/payload enums and [`record::build`].
//! * [`action`] — `$dnsrewrite` value grammar and the normalized action key.
//! * [`engine`] — the compiled rule snapshot and the query walk.
//! * [`payload`] — the request/reply layout shared with `ffi`.
//! * [`ffi`] — the C ABI the Go loader validates.

pub mod action;
pub mod engine;
pub mod ffi;
pub mod payload;
pub mod record;

pub use action::Action;
pub use engine::Engine;
pub use ffi::ABI_VERSION;
pub use record::{build, ParsedRecord, Record, SvcParam};

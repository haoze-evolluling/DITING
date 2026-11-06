//! Rewrite record kernel for the desktop service (`desktop/service/internal/core`).
//!
//! This is the only implementation left of `buildRewriteRR`: the supported record types, the value
//! grammar for every one of them, the SVCB parameter list and the target-domain check.
//! `internal/core/rewrite_native.go` loads the library at runtime (pure Go `dlopen`, no cgo), checks
//! [`ffi::ABI_VERSION`] and asks it for one typed record at a time. A missing artifact, a stale ABI
//! or a rejected payload fails the build, which fails `compileRewriteRecords` (a custom rewrite
//! rule) or `validateRewriteValue` (a `$dnsrewrite` modifier). There is no second parser to fall
//! back to, by design: two parsers would drift silently, and the value syntax is shared by both
//! entry points.
//!
//! The `dns.RR` itself is still built in Go, because the answer goes straight into a `dns.Msg`:
//! the reply carries the numeric record type plus its unpacked fields.
//!
//! Layout:
//! * [`record`] — the type tables, the record/payload enums and [`record::build`].
//! * [`payload`] — the request/reply layout shared with `ffi`.
//! * [`ffi`] — the C ABI the Go loader validates.

pub mod ffi;
pub mod payload;
pub mod record;

pub use ffi::ABI_VERSION;
pub use record::{build, ParsedRecord, Record, SvcParam};

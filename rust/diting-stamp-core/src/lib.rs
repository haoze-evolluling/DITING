//! Desktop service native core: `sdns://` DNS stamp parsing for `desktop/service` (Go).
//!
//! This is the only implementation left. `internal/core/stamp_native.go` loads the library at
//! runtime through purego, checks [`ffi::ABI_VERSION`] and asks it to parse; a missing artifact,
//! a stale ABI or a rejected payload fails `ParseServerStamp`, which fails the provider build.
//! There is no second parser to fall back to, by design: two parsers would drift silently.
//!
//! Layout:
//! * [`stamp`] — the byte-exact parser (`resolver_stamp.go` before the move) and the strings
//!   derived from a parsed stamp (`URL()` / `Server()`).
//! * [`ffi`] — the C ABI and the payload the Go side decodes.

pub mod ffi;
pub mod stamp;

pub use ffi::ABI_VERSION;
pub use stamp::{parse, Proto, Stamp, HASH_LEN};

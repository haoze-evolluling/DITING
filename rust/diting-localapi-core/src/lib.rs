//! A10: the loopback-only, token-guarded local HTTP API policy kernel. See [`policy`].
//!
//! The transport is the app's own `HttpServer`; this crate owns the two security decisions (loopback
//! only, bearer token) and the read-only route table, so the server cannot drift from them.

pub mod ffi;
pub mod policy;

pub use ffi::ABI_VERSION;
pub use policy::{authorize, route, validate_bind, Decision, Route, RouteOutcome, TOKEN_HEADER};

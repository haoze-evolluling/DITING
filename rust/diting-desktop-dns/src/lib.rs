//! The desktop DNS data plane.
//!
//! `context` carries one query through the fixed pipeline; `pipeline` executes the stages in the
//! same order the Go service registered them; `listener` owns the UDP/TCP/DoT/DoH/DoQ sockets.

// The cache-stage test fixture configures `CacheSettings` field by field; rewriting it through a
// struct literal would obscure which field each assertion depends on.
#![cfg_attr(test, allow(clippy::field_reassign_with_default))]

pub mod builder;
pub mod context;
pub mod encrypted;
pub mod pipeline;
pub mod server;
pub mod stages;

//! Desktop engine facades.
//!
//! The shared Android crates own every decision; this crate is the desktop orchestration around
//! them (conditional routes, group isolation, persistence, prefetch) and the state the IPC and DNS
//! crates read.

pub mod cache;
pub mod cert;
pub mod filter;
pub mod metrics;
pub mod mobileconfig;
pub mod querylog;
pub mod resolver;

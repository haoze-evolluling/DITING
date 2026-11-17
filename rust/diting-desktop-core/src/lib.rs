//! Desktop engine facades.
//!
//! The shared Android crates own every decision; this crate is the desktop orchestration around
//! them (conditional routes, group isolation, persistence, prefetch) and the state the IPC and DNS
//! crates read.

pub mod access;
pub mod cache;
pub mod cert;
pub mod clients;
pub mod filter;
pub mod hosts;
pub mod metrics;
pub mod mobileconfig;
pub mod querylog;
pub mod ratelimit;
pub mod resolver;
pub mod rewrite;
pub mod safesearch;
pub mod zone;

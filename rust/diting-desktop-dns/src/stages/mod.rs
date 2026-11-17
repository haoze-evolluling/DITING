//! The DNS pipeline stages.
//!
//! Each stage ports one Go middleware. Shared rules:
//! * `before` either passes (`Continue`), produces the whole answer (`Stop`), or fails;
//! * `after` runs in reverse order and only inspects or rewrites the finished response;
//! * attributes use the same string keys as the Go context so the query log, EDE and metrics see
//!   identical labels.
//!
//! Stages that consult hot-reloaded configuration hold a [`ConfigHandle`] and copy only the
//! fields they need while holding the read lock — never across an `.await`.

pub mod any;
pub mod block;
pub mod dns64;
pub mod ech;
pub mod ecs;
pub mod ede;
pub mod filter;
pub mod ipv6;
pub mod private_ptr;
pub mod rebind;
pub mod records;
pub mod sudn;
pub mod unqualified;
pub mod metrics;
pub mod util;
pub mod safesearch;
pub mod zone;
pub mod rewrite;
pub mod hosts;
pub mod ratelimit;
pub mod access;
pub mod client;
pub mod bogus;
pub mod filter_response;
pub mod cache;
pub mod forward;

use std::sync::{Arc, RwLock};

use diting_desktop_api::config::Config;

pub type ConfigHandle = Arc<RwLock<Config>>;

pub fn config_snapshot(handle: &ConfigHandle) -> Config {
    handle
        .read()
        .unwrap_or_else(|error| error.into_inner())
        .clone()
}

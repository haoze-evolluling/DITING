//! Client identification, aliases, groups and activity tracking.
//!
//! Facade over `client_groups.go` and `client_resolver.go`. The query path uses
//! [`ClientDirectory::identify`] (never blocking) and [`ClientDirectory::group`];
//! reverse DNS is an explicit async call from the DNS stage.

mod directory;
mod group;

pub use directory::{
    cache_ttl_millis, ClientDirectory, DEFAULT_CACHE_TTL_MS, MAX_CLIENT_CACHE, MAX_CLIENT_STATS,
    MAX_CONCURRENT_RDNS,
};
pub use group::GroupResolver;

use std::net::IpAddr;

/// Group id returned when no configured group matches.
pub const DEFAULT_GROUP: &str = "default";

/// Runtime identification and statistics for one client address.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientInfo {
    pub ip: IpAddr,
    pub name: String,
    pub group: String,
    /// Unix milliseconds of the last query.
    pub last_seen_ms: i64,
    pub query_count: u64,
}

#[cfg(test)]
mod tests;

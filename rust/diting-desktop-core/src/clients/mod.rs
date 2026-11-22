mod directory;
mod group;

pub use directory::{
    cache_ttl_millis, ClientDirectory, DEFAULT_CACHE_TTL_MS, MAX_CLIENT_CACHE, MAX_CLIENT_STATS,
    MAX_CONCURRENT_RDNS,
};
pub use group::GroupResolver;

use std::net::IpAddr;

pub const DEFAULT_GROUP: &str = "default";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientInfo {
    pub ip: IpAddr,
    pub name: String,
    pub group: String,
    pub last_seen_ms: i64,
    pub query_count: u64,
}

#[cfg(test)]
mod tests;

pub mod backup;
pub mod cache;
pub mod client;
pub mod dns;
pub mod dns_features;
pub mod duration;
pub mod filter;
pub mod openwrt;
pub mod paths;
pub mod querylog;
pub mod rewrite_zone;
pub mod security;
pub mod store;
pub mod upstream;

pub(crate) mod serde_util;

pub use cache::CacheConfig;
pub use client::{ClientAlias, ClientConfig, ClientGroup};
pub use dns::{DNSConfig, IPCConfig, LoginBgConfig, TakeoverConfig, WebConfig};
pub use dns_features::{
    AccessControlConfig, DNS64Config, ECSConfig, HostsConfig, RateLimitConfig, RebindConfig,
};
pub use duration::{parse_go_duration, DurationParseError, DurationValue};
pub use filter::{BlockingSchedule, FilterConfig, FilterList};
pub use openwrt::{
    OpenWrtConfig, DEFAULT_DNSMASQ_AUX_PORT, DEFAULT_UPSTREAM_LISTEN_PORT,
    OPENWRT_MODE_DNSMASQ_UPSTREAM, OPENWRT_MODE_REPLACE_DNSMASQ,
};
pub use querylog::QueryLogConfig;
pub use rewrite_zone::{RewriteConfig, RewriteRecord, RewriteRule, ZoneConfig, ZoneEntry};
pub use security::{
    CertConfig, EncryptedDNSConfig, ReverseProxyConfig, SafeBrowsingConfig, SafeSearchConfig,
};
pub use store::{default_config_path, load_config, save_config, ConfigStore, FileConfigStore};
pub use upstream::{BootstrapConfig, BootstrapServer, ProviderConfig, ResolverConfig};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Config {
    pub dns: DNSConfig,
    pub upstream: ResolverConfig,
    pub ipc: IPCConfig,
    pub takeover: TakeoverConfig,
    pub cache: CacheConfig,
    pub filter: FilterConfig,
    pub hosts: HostsConfig,
    pub rebind: RebindConfig,
    pub access: AccessControlConfig,
    pub rate_limit: RateLimitConfig,
    pub dns64: DNS64Config,
    pub rewrite: RewriteConfig,
    pub zone: ZoneConfig,
    pub safe_search: SafeSearchConfig,
    pub safe_browsing: SafeBrowsingConfig,
    pub encrypted: EncryptedDNSConfig,
    pub client: ClientConfig,
    pub ecs: ECSConfig,
    #[serde(rename = "querylog")]
    pub query_log: QueryLogConfig,
    pub web: WebConfig,
    #[serde(default)]
    pub openwrt: OpenWrtConfig,
}

impl Config {
    pub fn normalize(&mut self) {
        self.dns.normalize();
        if self.ipc.listen_address.is_empty() {
            self.ipc.listen_address = IPCConfig::default().listen_address;
        }
        self.upstream.normalize();
        self.web.normalize();
        self.openwrt.normalize();
        self.cache.normalize();
        self.filter.normalize();
        self.rewrite.normalize();
        self.zone.normalize();
        self.safe_search.normalize();
        self.safe_browsing.normalize();
        self.encrypted.normalize();
        self.client.normalize();
        self.query_log.normalize();
    }
}

pub(crate) fn timestamp_nanos() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests;

use diting_desktop_api::config::{CacheConfig, Config, QueryLogConfig, ResolverConfig};
use diting_desktop_core::cache::CacheSettings;
use diting_desktop_core::querylog::Config as QueryLogSettings;
use diting_desktop_core::resolver::settings::{
    BootstrapServerSettings, BootstrapSettings, ProviderSettings, ResolverSettings,
};

pub fn resolver_settings(config: &ResolverConfig) -> ResolverSettings {
    ResolverSettings {
        mode: config.mode.clone(),
        providers: config.providers.iter().map(provider_settings).collect(),
        bootstrap: BootstrapSettings {
            enabled: config.bootstrap.enabled,
            servers: config
                .bootstrap
                .servers
                .iter()
                .map(|server| BootstrapServerSettings {
                    id: server.id.clone(),
                    name: server.name.clone(),
                    address: server.address.clone(),
                    weight: server.weight,
                })
                .collect(),
        },
        conditional_routes: config
            .conditional_routes
            .iter()
            .map(|(suffix, provider)| (suffix.clone(), provider.clone()))
            .collect(),
        edns_padding: i64::from(config.edns_padding),
        fallback_providers: config
            .fallback_providers
            .iter()
            .map(provider_settings)
            .collect(),
        fallback_timeout_ms: i64::from(config.fallback_timeout_ms),
        fallback_on_rcode: config.fallback_on_rcode.clone(),
        fallback_on_error: config.fallback_on_error,
        race_max_parallel: 0,
    }
}

const OPENWRT_PRIVATE_PTR_ZONES: &[&str] = &[
    "10.in-addr.arpa",
    "168.192.in-addr.arpa",
    "16.172.in-addr.arpa",
    "17.172.in-addr.arpa",
    "18.172.in-addr.arpa",
    "19.172.in-addr.arpa",
    "20.172.in-addr.arpa",
    "21.172.in-addr.arpa",
    "22.172.in-addr.arpa",
    "23.172.in-addr.arpa",
    "24.172.in-addr.arpa",
    "25.172.in-addr.arpa",
    "26.172.in-addr.arpa",
    "27.172.in-addr.arpa",
    "28.172.in-addr.arpa",
    "29.172.in-addr.arpa",
    "30.172.in-addr.arpa",
    "31.172.in-addr.arpa",
    "c.f.ip6.arpa",
    "d.f.ip6.arpa",
];

pub fn resolver_settings_for_runtime(
    config: &Config,
    openwrt_local_domain: Option<&str>,
) -> ResolverSettings {
    let mut settings = resolver_settings(&config.upstream);
    if let Some(domain) = openwrt_local_domain {
        if config.openwrt.is_replace_mode() && config.openwrt.forward_local_domain {
            let target = format!("127.0.0.1:{}", config.openwrt.dnsmasq_port);
            let cleaned = domain.trim().trim_matches('.').to_ascii_lowercase();
            if !cleaned.is_empty() {
                settings
                    .conditional_routes
                    .entry(cleaned)
                    .or_insert_with(|| target.clone());
            }
            for &zone in OPENWRT_PRIVATE_PTR_ZONES {
                settings
                    .conditional_routes
                    .entry(zone.to_string())
                    .or_insert_with(|| target.clone());
            }
        }
    }
    settings
}

fn provider_settings(provider: &diting_desktop_api::config::ProviderConfig) -> ProviderSettings {
    ProviderSettings {
        id: provider.id.clone(),
        protocol: provider.protocol.clone(),
        server: provider.server.clone(),
        url: provider.url.clone(),
        weight: i64::from(provider.weight),
        pin: provider.pin.clone(),
    }
}

pub fn cache_settings(config: &CacheConfig) -> CacheSettings {
    CacheSettings {
        enabled: config.enabled,
        max_entries: config.max_entries,
        mode: config.mode.clone(),
        max_ttl_seconds: config.max_ttl_seconds,
        fixed_ttl_seconds: config.fixed_ttl_seconds,
        min_ttl_enabled: config.min_ttl_enabled,
        min_ttl_seconds: config.min_ttl_seconds,
        stale_fallback_enabled: config.stale_fallback_enabled,
        stale_fallback_seconds: config.stale_fallback_seconds,
        negative_ttl_enabled: config.negative_ttl_enabled,
        negative_ttl_seconds: config.negative_ttl_seconds,
        optimistic: config.optimistic,
        prefetch_enabled: config.prefetch_enabled,
        prefetch_threshold: config.prefetch_threshold,
        prefetch_before_expiry_ms: config.prefetch_before_expiry_ms,
        exclude_patterns: config.exclude_patterns.clone(),
    }
}

pub fn querylog_settings(config: &QueryLogConfig) -> QueryLogSettings {
    QueryLogSettings {
        enabled: config.enabled,
        max_entries: config.max_entries,
        file_enabled: config.file_enabled,
        retention_days: config.retention_days,
        log_clients: config.log_clients,
        data_dir: config.data_dir.clone(),
    }
}

pub fn group_upstreams(config: &Config) -> Vec<(String, Vec<String>)> {
    if !config.client.groups_enabled {
        return Vec::new();
    }
    config
        .client
        .groups
        .iter()
        .filter(|group| group.enabled && !group.upstream_ids.is_empty())
        .map(|group| (group.id.clone(), group.upstream_ids.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_round_trip_to_runtime_settings() {
        let config = Config::default();
        let resolver = resolver_settings(&config.upstream);
        assert_eq!(resolver.providers.len(), config.upstream.providers.len());
        assert_eq!(resolver.providers[0].protocol, "DOT");
        assert_eq!(
            resolver.bootstrap.servers.len(),
            config.upstream.bootstrap.servers.len()
        );
        let cache = cache_settings(&config.cache);
        assert_eq!(cache.max_entries, config.cache.max_entries);
        let querylog = querylog_settings(&config.query_log);
        assert_eq!(querylog.max_entries, config.query_log.max_entries);
    }

    #[test]
    fn group_upstreams_respect_the_enabled_switch() {
        let mut config = Config::default();
        config.client.groups_enabled = false;
        config.client.groups = vec![diting_desktop_api::config::ClientGroup {
            id: "kids".into(),
            enabled: true,
            upstream_ids: vec!["p1".into()],
            ..Default::default()
        }];
        assert!(group_upstreams(&config).is_empty());
        config.client.groups_enabled = true;
        assert_eq!(group_upstreams(&config).len(), 1);
    }
}

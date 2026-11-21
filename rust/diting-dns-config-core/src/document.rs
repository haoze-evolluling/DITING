use diting_config_core::mode;
use serde::Serialize;

use crate::presets;
use crate::protocol::{self, Protocol};
use crate::providers::{self, Provider};
use crate::upstreams::{self, ServerUpstream};

const DEFAULT_SELECTED_PROVIDER_ID: &str = "preset_alidns_dns";
const DEFAULT_RACE_IDS: [&str; 2] = ["preset_alidns_dns", "preset_dnspod_dns"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BootstrapEntry {
    pub id: String,
    pub name: String,
    pub ip: String,
}

impl BootstrapEntry {
    pub fn new(id: &str, name: &str, ip: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            ip: ip.to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DynamicInput {
    pub enabled: bool,
    pub request_threshold: i32,
    pub window_seconds: i32,
    pub nxdomain_seconds: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PrivacyInput {
    pub block_record_types: Vec<String>,
    pub rebinding_protection: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Dns64Input {
    pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RateLimitInput {
    pub enabled: bool,
    pub rate: i32,
    pub burst: i32,
    pub ipv4_prefix: i32,
    pub ipv6_prefix: i32,
    pub exempt: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConnectionRateLimitInput {
    pub enabled: bool,
    pub rate: i32,
    pub burst: i32,
}

impl Default for ConnectionRateLimitInput {
    fn default() -> Self {
        Self {
            enabled: false,
            rate: 50,
            burst: 100,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CacheInput {
    pub enabled: bool,
    pub ttl_scale_percent: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TunnelSettings {
    pub mode_raw: String,
    pub selected_provider_id: String,
    pub smart_prediction_provider_ids: Vec<String>,
    pub parallel_race_provider_ids: Vec<String>,
    pub primary_backup_provider_ids: Vec<String>,
    pub user_providers_json: Option<String>,
    pub bootstrap_enabled: bool,
    pub bootstrap_preset_ids: Vec<String>,
    pub bootstrap_custom_json: Option<String>,
    pub block_response_mode: String,
    pub cache: CacheInput,
    pub dynamic: DynamicInput,
    pub privacy: PrivacyInput,
    pub dns64: Dns64Input,
    pub connection_rate_limit: ConnectionRateLimitInput,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TunnelConfig {
    pub mode: String,
    pub providers: Vec<Provider>,
    pub bootstrap: Vec<BootstrapEntry>,
    pub document: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerSettings {
    pub resolution_mode_raw: String,
    pub selected_upstream_id: String,
    pub smart_prediction_provider_ids: Vec<String>,
    pub parallel_race_provider_ids: Vec<String>,
    pub primary_backup_provider_ids: Vec<String>,
    pub port: i32,
    pub ad_block_enabled: bool,
    pub cache_preset_raw: String,
    pub cache_enabled: bool,
    pub block_response_mode: String,
    pub dynamic: DynamicInput,
    pub custom_upstreams_json: Option<String>,
    pub privacy: PrivacyInput,
    pub dns64: Dns64Input,
    pub rate_limit: RateLimitInput,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerConfig {
    pub port: i32,
    pub mode: String,
    pub providers: Vec<ServerUpstream>,
    pub document: String,
}

const MAX_TTL_SECONDS: i32 = 86_400;
const STALE_FALLBACK_SECONDS: i32 = 300;
const NEGATIVE_TTL_SECONDS: i32 = 30;
const MIN_SCALE_PERCENT: i32 = 10;
const MAX_SCALE_PERCENT: i32 = 500;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TunnelCacheDocument {
    enabled: bool,
    ttl_scale_percent: i32,
    max_ttl_seconds: i32,
    stale_fallback_enabled: bool,
    stale_fallback_seconds: i32,
    negative_ttl_enabled: bool,
    negative_ttl_seconds: i32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ServerCacheDocument {
    enabled: bool,
    mode: String,
    max_ttl_seconds: i32,
    fixed_ttl_seconds: i32,
    min_ttl_enabled: bool,
    min_ttl_seconds: i32,
    stale_fallback_enabled: bool,
    stale_fallback_seconds: i32,
    negative_ttl_enabled: bool,
    negative_ttl_seconds: i32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DynamicDocument {
    enabled: bool,
    request_threshold: i32,
    window_seconds: i32,
    nx_domain_duration_seconds: i32,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PrivacyDocument {
    block_record_types: Vec<String>,
    rebinding_protection: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Dns64Document {
    enabled: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitDocument {
    enabled: bool,
    rate: i32,
    burst: i32,
    ipv4_prefix: i32,
    ipv6_prefix: i32,
    exempt: Vec<String>,
}

#[derive(Serialize)]
struct ConnectionRateLimitDocument {
    enabled: bool,
    rate: i32,
    burst: i32,
}

#[derive(Serialize)]
struct ProviderDocument<'a> {
    id: &'a str,
    protocol: &'a str,
    server: String,
    url: &'a str,
}

#[derive(Serialize)]
struct BootstrapEntryDocument<'a> {
    id: &'a str,
    name: &'a str,
    ip: &'a str,
}

#[derive(Serialize)]
struct BootstrapDocument<'a> {
    enabled: bool,
    ips: Vec<BootstrapEntryDocument<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TunnelDocument<'a, C> {
    mode: &'a str,
    block_response: &'a str,
    dynamic_response: DynamicDocument,
    cache: C,
    providers: Vec<ProviderDocument<'a>>,
    bootstrap: BootstrapDocument<'a>,
    privacy: PrivacyDocument,
    dns64: Dns64Document,
    #[serde(skip_serializing_if = "Option::is_none")]
    rate_limit: Option<RateLimitDocument>,
    #[serde(skip_serializing_if = "Option::is_none")]
    connection_rate_limit: Option<ConnectionRateLimitDocument>,
}

fn clamp(value: i32, low: i32, high: i32) -> i32 {
    value.clamp(low, high)
}

fn find<'a>(catalog: &'a [Provider], id: &str) -> Option<&'a Provider> {
    catalog.iter().rev().find(|provider| provider.id == id)
}

fn pick(catalog: &[Provider], ids: &[String]) -> Vec<Provider> {
    ids.iter()
        .filter_map(|id| find(catalog, id).cloned())
        .collect()
}

fn valid_mode(raw: &str) -> &str {
    match raw {
        mode::MODE_SINGLE => mode::MODE_SINGLE,
        mode::MODE_SMART_PREDICTION => mode::MODE_SMART_PREDICTION,
        mode::MODE_PARALLEL_RACE => mode::MODE_PARALLEL_RACE,
        mode::MODE_PRIMARY_BACKUP => mode::MODE_PRIMARY_BACKUP,
        _ => mode::MODE_SINGLE,
    }
}

fn provider_document(provider: &Provider) -> ProviderDocument<'_> {
    ProviderDocument {
        id: &provider.id,
        protocol: protocol::go_value(provider.protocol),
        server: if provider.protocol == Protocol::Doh {
            String::new()
        } else {
            provider.host_port()
        },
        url: &provider.url,
    }
}

fn upstream_document(upstream: &ServerUpstream) -> ProviderDocument<'_> {
    ProviderDocument {
        id: &upstream.id,
        protocol: protocol::go_value(upstream.protocol),
        server: if upstream.protocol == Protocol::Doh {
            String::new()
        } else {
            upstream.host_port()
        },
        url: if upstream.protocol == Protocol::Doh {
            &upstream.address
        } else {
            ""
        },
    }
}

fn cache_document(input: &CacheInput) -> TunnelCacheDocument {
    TunnelCacheDocument {
        enabled: input.enabled,
        ttl_scale_percent: clamp(
            input.ttl_scale_percent,
            MIN_SCALE_PERCENT,
            MAX_SCALE_PERCENT,
        ),
        max_ttl_seconds: MAX_TTL_SECONDS,
        stale_fallback_enabled: true,
        stale_fallback_seconds: STALE_FALLBACK_SECONDS,
        negative_ttl_enabled: true,
        negative_ttl_seconds: NEGATIVE_TTL_SECONDS,
    }
}

fn privacy_document(input: &PrivacyInput) -> PrivacyDocument {
    PrivacyDocument {
        block_record_types: input.block_record_types.clone(),
        rebinding_protection: input.rebinding_protection,
    }
}

fn rate_limit_document(input: &RateLimitInput) -> RateLimitDocument {
    RateLimitDocument {
        enabled: input.enabled,
        rate: input.rate,
        burst: input.burst,
        ipv4_prefix: input.ipv4_prefix,
        ipv6_prefix: input.ipv6_prefix,
        exempt: input.exempt.clone(),
    }
}

fn connection_rate_limit_document(input: &ConnectionRateLimitInput) -> ConnectionRateLimitDocument {
    ConnectionRateLimitDocument {
        enabled: input.enabled,
        rate: clamp(input.rate, 5, 1000),
        burst: clamp(input.burst, 10, 2000),
    }
}

fn dynamic_document(input: &DynamicInput) -> DynamicDocument {
    DynamicDocument {
        enabled: input.enabled,
        request_threshold: clamp(input.request_threshold, 2, 100),
        window_seconds: clamp(input.window_seconds, 10, 300),
        nx_domain_duration_seconds: clamp(input.nxdomain_seconds, 60, 3600),
    }
}

fn bootstrap_entries(
    enabled: bool,
    preset_bootstrap: &[BootstrapEntry],
    selected_ids: &[String],
    custom_json: Option<&str>,
) -> Vec<BootstrapEntry> {
    if !enabled {
        return Vec::new();
    }
    let mut entries: Vec<BootstrapEntry> = preset_bootstrap
        .iter()
        .filter(|entry| selected_ids.iter().any(|id| id == &entry.id))
        .cloned()
        .collect();
    for row in crate::bootstrap::parse_custom(custom_json) {
        if !row.enabled {
            continue;
        }
        entries.push(BootstrapEntry::new(&row.id, &row.name, &row.ip));
    }
    entries
}

pub fn build_tunnel(
    settings: &TunnelSettings,
    preset_providers: &[Provider],
    preset_bootstrap: &[BootstrapEntry],
) -> TunnelConfig {
    let mode = valid_mode(&settings.mode_raw).to_string();
    let mut catalog: Vec<Provider> = preset_providers.to_vec();
    catalog.extend(providers::parse_user_providers(
        settings.user_providers_json.as_deref(),
    ));

    let selected = find(&catalog, &settings.selected_provider_id)
        .or_else(|| find(&catalog, DEFAULT_SELECTED_PROVIDER_ID))
        .or_else(|| preset_providers.first())
        .cloned();

    let race_ids = |ids: &[String]| -> Vec<String> {
        if ids.is_empty() {
            DEFAULT_RACE_IDS.iter().map(|id| id.to_string()).collect()
        } else {
            ids.to_vec()
        }
    };
    let authoritative = |candidates: Vec<Provider>| -> Vec<Provider> {
        if candidates.len() >= 2 {
            candidates
        } else {
            selected.iter().cloned().collect()
        }
    };

    let picked = match mode.as_str() {
        mode::MODE_SMART_PREDICTION => authoritative(pick(
            &catalog,
            &race_ids(&settings.smart_prediction_provider_ids),
        )),
        mode::MODE_PARALLEL_RACE => authoritative(pick(
            &catalog,
            &race_ids(&settings.parallel_race_provider_ids),
        )),
        mode::MODE_PRIMARY_BACKUP => authoritative(pick(
            &catalog,
            &race_ids(&settings.primary_backup_provider_ids),
        )),
        _ => selected.iter().cloned().collect(),
    };

    let bootstrap = bootstrap_entries(
        settings.bootstrap_enabled,
        preset_bootstrap,
        &settings.bootstrap_preset_ids,
        settings.bootstrap_custom_json.as_deref(),
    );

    let document = TunnelDocument {
        mode: &mode,
        block_response: protocol::block_response(&settings.block_response_mode),
        dynamic_response: dynamic_document(&settings.dynamic),
        cache: cache_document(&settings.cache),
        providers: picked.iter().map(provider_document).collect(),
        bootstrap: BootstrapDocument {
            enabled: settings.bootstrap_enabled,
            ips: bootstrap
                .iter()
                .map(|entry| BootstrapEntryDocument {
                    id: &entry.id,
                    name: &entry.name,
                    ip: &entry.ip,
                })
                .collect(),
        },
        privacy: privacy_document(&settings.privacy),
        dns64: Dns64Document {
            enabled: settings.dns64.enabled,
        },
        rate_limit: None,
        connection_rate_limit: Some(connection_rate_limit_document(
            &settings.connection_rate_limit,
        )),
    };
    let document = serde_json::to_string(&document).unwrap_or_else(|_| String::from("{}"));
    TunnelConfig {
        mode,
        providers: picked,
        bootstrap,
        document,
    }
}

pub fn build_server(
    settings: &ServerSettings,
    preset_upstreams: &[ServerUpstream],
) -> Option<ServerConfig> {
    let mut catalog: Vec<ServerUpstream> = preset_upstreams.to_vec();
    catalog.extend(upstreams::parse_custom_upstreams(
        settings.custom_upstreams_json.as_deref(),
    ));
    let pick_upstream = |id: &str| -> Option<ServerUpstream> {
        catalog
            .iter()
            .rev()
            .find(|upstream| upstream.id == id)
            .cloned()
    };
    let selected = pick_upstream(&settings.selected_upstream_id)
        .or_else(|| pick_upstream(DEFAULT_SELECTED_PROVIDER_ID))
        .or_else(|| preset_upstreams.first().cloned())?;

    let mode = valid_mode(&settings.resolution_mode_raw).to_string();
    let pick_many = |ids: &[String]| -> Vec<ServerUpstream> {
        ids.iter().filter_map(|id| pick_upstream(id)).collect()
    };
    let race_ids = |ids: &[String]| -> Vec<String> {
        if ids.is_empty() {
            DEFAULT_RACE_IDS.iter().map(|id| id.to_string()).collect()
        } else {
            ids.to_vec()
        }
    };
    let authoritative = |candidates: Vec<ServerUpstream>| -> Vec<ServerUpstream> {
        if candidates.len() >= 2 {
            candidates
        } else {
            vec![selected.clone()]
        }
    };
    let providers = match mode.as_str() {
        mode::MODE_SMART_PREDICTION => authoritative(pick_many(&race_ids(
            &settings.smart_prediction_provider_ids,
        ))),
        mode::MODE_PARALLEL_RACE => {
            authoritative(pick_many(&race_ids(&settings.parallel_race_provider_ids)))
        }
        mode::MODE_PRIMARY_BACKUP => {
            authoritative(pick_many(&race_ids(&settings.primary_backup_provider_ids)))
        }
        _ => vec![selected.clone()],
    };

    let (values, negative_ttl_seconds) = presets::server_cache_document(&settings.cache_preset_raw);
    let cache = ServerCacheDocument {
        enabled: settings.cache_enabled,
        mode: values.mode.to_string(),
        max_ttl_seconds: values.max_ttl_seconds,
        fixed_ttl_seconds: values.fixed_ttl_seconds,
        min_ttl_enabled: values.min_ttl_enabled,
        min_ttl_seconds: values.min_ttl_seconds,
        stale_fallback_enabled: values.stale_fallback_enabled,
        stale_fallback_seconds: values.stale_fallback_seconds,
        negative_ttl_enabled: true,
        negative_ttl_seconds,
    };
    let document = TunnelDocument {
        mode: &mode,
        block_response: protocol::block_response(&settings.block_response_mode),
        dynamic_response: dynamic_document(&settings.dynamic),
        cache,
        providers: providers.iter().map(upstream_document).collect(),
        bootstrap: BootstrapDocument {
            enabled: false,
            ips: Vec::new(),
        },
        privacy: privacy_document(&settings.privacy),
        dns64: Dns64Document {
            enabled: settings.dns64.enabled,
        },
        rate_limit: Some(rate_limit_document(&settings.rate_limit)),
        connection_rate_limit: None,
    };
    let document = serde_json::to_string(&document).unwrap_or_else(|_| String::from("{}"));
    Some(ServerConfig {
        port: settings.port,
        mode,
        providers,
        document,
    })
}

#[cfg(test)]
mod tests;

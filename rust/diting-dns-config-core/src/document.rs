//! The two JSON documents the engines read: the tunnel's `ApplyDNSConfig` and server mode's
//! `DnsServerEngine.applyDnsConfig`.
//!
//! Both are assembled here in one pass, because the cache / block / dynamic keys are the same shape
//! in both and the providers list is what the mode selection picked. Field order follows 1.4.3 so a
//! diff of the pushed document stays readable.

use diting_config_core::mode;
use serde::Serialize;

use crate::presets;
use crate::protocol::{self, Protocol};
use crate::providers::{self, Provider};
use crate::upstreams::{self, ServerUpstream};

const DEFAULT_SELECTED_PROVIDER_ID: &str = "preset_alidns_dns";
const DEFAULT_RACE_IDS: [&str; 2] = ["preset_alidns_dns", "preset_dnspod_dns"];

/// One bootstrap entry: preset rows and the custom `bootstrap_custom_json` rows end up here.
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

/// The fixed block-response mode plus the dynamic policy, both from prefs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DynamicInput {
    pub enabled: bool,
    pub request_threshold: i32,
    pub window_seconds: i32,
    pub nxdomain_seconds: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CacheInput {
    pub enabled: bool,
    pub mode: String,
    pub max_ttl_seconds: i32,
    pub fixed_ttl_seconds: i32,
    pub min_ttl_enabled: bool,
    pub min_ttl_seconds: i32,
    pub stale_fallback_enabled: bool,
    pub stale_fallback_seconds: i32,
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
    /// `single` / `smart_prediction` / `parallel_race` / `primary_backup`, the same scheduling
    /// modes the tunnel uses.
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerConfig {
    pub port: i32,
    /// The scheduling mode actually written to the document (`single` when the raw value is
    /// unknown).
    pub mode: String,
    /// The upstreams in engine attempt order: one for `single`, the picked race list otherwise.
    pub providers: Vec<ServerUpstream>,
    pub document: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheDocument {
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
struct TunnelDocument<'a> {
    mode: &'a str,
    block_response: &'a str,
    dynamic_response: DynamicDocument,
    cache: CacheDocument,
    providers: Vec<ProviderDocument<'a>>,
    bootstrap: BootstrapDocument<'a>,
}

fn clamp(value: i32, low: i32, high: i32) -> i32 {
    value.clamp(low, high)
}

/// Last row wins, mirroring the Dart map built in catalog order (presets first, custom after).
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

/// Server mode's upstream row as a document provider. The address is a bare host for PLAIN / DOT
/// and the endpoint URL for DoH, so `server` and `url` split the same way as the tunnel's.
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

fn cache_document(input: &CacheInput) -> CacheDocument {
    CacheDocument {
        enabled: input.enabled,
        mode: input.mode.clone(),
        max_ttl_seconds: clamp(input.max_ttl_seconds, 30, 86400),
        fixed_ttl_seconds: clamp(input.fixed_ttl_seconds, 30, 86400),
        min_ttl_enabled: input.min_ttl_enabled,
        min_ttl_seconds: clamp(input.min_ttl_seconds, 30, 86400),
        stale_fallback_enabled: input.stale_fallback_enabled,
        stale_fallback_seconds: clamp(input.stale_fallback_seconds, 30, 86400),
        // 1.4.3 has no negative-TTL UI; the Go defaults are kept explicitly.
        negative_ttl_enabled: true,
        negative_ttl_seconds: 30,
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

/// Bootstrap entries: the selected presets in catalog order, then the enabled custom rows.
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

    // The four scheduling modes are the tunnel's, so the server mode races on the same engine
    // scheduler. Below two candidates a race would be pointless, so it falls back to the selected
    // upstream exactly like the tunnel does.
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
    let cache = CacheDocument {
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
        // Server mode never used bootstrap: LAN clients resolve through this device.
        bootstrap: BootstrapDocument {
            enabled: false,
            ips: Vec::new(),
        },
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

use serde::Deserialize;

use diting_config_core::dns_config::{normalize, NormalizedProvider, Provider as ConfigProvider};
use diting_config_core::dynamic::DynamicBlock;
use diting_config_core::protocol::Protocol;
use diting_dns_cache_core::policy::{
    Config as CacheConfig, TtlMode, DEFAULT_TTL_SCALE_PERCENT, MAX_TTL_SCALE_PERCENT,
    MAX_TTL_SECONDS, MIN_TTL_SCALE_PERCENT,
};
use diting_dns_core::block::BlockConfig;

use crate::connection_limit::Config as ConnectionRateLimitConfig;
use crate::error::{EngineError, EngineResult};

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProviderJson {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub protocol: String,
    #[serde(default)]
    pub server: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub weight: i64,
    #[serde(default)]
    pub pin: String,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DynamicResponseJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub request_threshold: i64,
    #[serde(default)]
    pub window_seconds: i64,
    #[serde(default)]
    pub nx_domain_duration_seconds: i64,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CacheJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub ttl_scale_percent: i64,
    #[serde(default)]
    pub max_ttl_seconds: i64,
    #[serde(default)]
    pub stale_fallback_enabled: bool,
    #[serde(default)]
    pub stale_fallback_seconds: i64,
    #[serde(default)]
    pub negative_ttl_enabled: bool,
    #[serde(default)]
    pub negative_ttl_seconds: i64,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BootstrapIpJson {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub ip: String,
    #[serde(default)]
    pub weight: f64,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrivacyJson {
    #[serde(default)]
    pub block_record_types: Vec<String>,
    #[serde(default)]
    pub rebinding_protection: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Dns64Json {
    #[serde(default)]
    pub enabled: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RateLimitJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub rate: i64,
    #[serde(default)]
    pub burst: i64,
    #[serde(default)]
    pub ipv4_prefix: i64,
    #[serde(default)]
    pub ipv6_prefix: i64,
    #[serde(default)]
    pub exempt: Vec<String>,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConnectionRateLimitJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub rate: i64,
    #[serde(default)]
    pub burst: i64,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BootstrapJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub ips: Vec<BootstrapIpJson>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DnsConfigJson {
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub providers: Vec<ProviderJson>,
    #[serde(default)]
    pub block_response: String,
    #[serde(default)]
    pub dynamic_response: DynamicResponseJson,
    #[serde(default)]
    pub cache: CacheJson,
    #[serde(default)]
    pub bootstrap: BootstrapJson,
    #[serde(default)]
    pub privacy: PrivacyJson,
    #[serde(default)]
    pub dns64: Dns64Json,
    #[serde(default)]
    pub rate_limit: RateLimitJson,
    #[serde(default)]
    pub connection_rate_limit: Option<ConnectionRateLimitJson>,
    #[serde(default)]
    pub race_max_parallel: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub id: String,
    pub protocol: Protocol,
    pub server: String,
    pub url: String,
    pub weight: i64,
    pub pin: String,
}

impl Provider {
    fn from_parts(provider: &NormalizedProvider, source: &ProviderJson) -> Self {
        Self {
            id: provider.id.clone(),
            protocol: provider.protocol,
            server: provider.server.clone(),
            url: provider.url.clone(),
            weight: provider.weight,
            pin: source.pin.clone(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct DnsConfig {
    pub mode: &'static str,
    pub providers: Vec<Provider>,
    pub block_response: u32,
    pub dynamic_response: BlockConfig,
    pub cache: CacheConfig,
    pub bootstrap: BootstrapJson,
    pub privacy: PrivacyPolicy,
    pub dns64: bool,
    pub rate_limit: diting_ratelimit_core::Config,
    pub connection_rate_limit: ConnectionRateLimitConfig,
    pub race_max_parallel: i64,
    /// 解析阶段丢弃、不再支持的上游协议，供 Resolver 汇总到 skipped 日志。
    pub skipped: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PrivacyPolicy {
    pub blocked_qtypes: Vec<u16>,
    pub rebinding_protection: bool,
}

impl DnsConfig {
    pub fn parse(payload: &str) -> EngineResult<DnsConfigJson> {
        let mut stream = serde_json::Deserializer::from_str(payload).into_iter::<DnsConfigJson>();
        let document = match stream.next() {
            Some(Ok(document)) => document,
            Some(Err(error)) => {
                return Err(EngineError::config_parse(format!(
                    "parse DNS config: {error}"
                )))
            }
            None => {
                return Err(EngineError::config_parse(
                    "parse DNS config: EOF".to_string(),
                ))
            }
        };
        match stream.next() {
            None => Ok(document),
            Some(Ok(_)) => Err(EngineError::config_parse(
                "parse DNS config: trailing data".to_string(),
            )),
            Some(Err(error)) => Err(EngineError::config_parse(format!(
                "parse DNS config: {error}"
            ))),
        }
    }

    pub fn from_json(payload: &str) -> EngineResult<DnsConfig> {
        let document = Self::parse(payload)?;
        Self::from_document(&document)
    }

    pub fn from_document(document: &DnsConfigJson) -> EngineResult<DnsConfig> {
        let dynamic = DynamicBlock::normalized(
            document.dynamic_response.enabled,
            document.dynamic_response.request_threshold,
            document.dynamic_response.window_seconds,
            document.dynamic_response.nx_domain_duration_seconds,
        );

        let mut incoming = Vec::with_capacity(document.providers.len());
        let mut sources = Vec::with_capacity(document.providers.len());
        let mut skipped = Vec::new();
        for provider in &document.providers {
            let text = provider.protocol.trim().to_ascii_uppercase();
            if matches!(text.as_str(), "DOQ" | "QUIC") {
                let name = if provider.id.is_empty() {
                    format!("provider {}", incoming.len())
                } else {
                    format!("provider {}", provider.id)
                };
                skipped.push(format!("{name}: DoQ is no longer supported"));
                continue;
            }
            let protocol = if matches!(text.as_str(), "DOH3" | "H3") {
                "DOH".to_string()
            } else {
                provider.protocol.clone()
            };
            incoming.push(ConfigProvider {
                id: provider.id.clone(),
                protocol,
                server: provider.server.clone(),
                url: provider.url.clone(),
                weight: provider.weight,
            });
            sources.push(provider);
        }

        let normalized = normalize(&document.mode, &document.block_response, dynamic, &incoming)
            .map_err(EngineError::config_invalid)?;

        Ok(DnsConfig {
            mode: normalized.mode,
            providers: normalized
                .providers
                .iter()
                .zip(sources.iter())
                .map(|(provider, source)| Provider::from_parts(provider, source))
                .collect(),
            block_response: normalized.block_response.code() as u32,
            dynamic_response: BlockConfig {
                enabled: normalized.dynamic.enabled,
                request_threshold: normalized.dynamic.request_threshold.max(0) as u32,
                window_ns: normalized
                    .dynamic
                    .window_seconds
                    .saturating_mul(1_000_000_000),
                nx_domain_ns: normalized
                    .dynamic
                    .nxdomain_seconds
                    .saturating_mul(1_000_000_000),
            },
            cache: cache_config(&document.cache),
            bootstrap: document.bootstrap.clone(),
            privacy: privacy_policy(&document.privacy),
            dns64: document.dns64.enabled,
            rate_limit: rate_limit_config(&document.rate_limit),
            connection_rate_limit: connection_rate_limit_config(
                document.connection_rate_limit.as_ref(),
            ),
            race_max_parallel: document.race_max_parallel.unwrap_or(0),
            skipped,
        })
    }
}

fn connection_rate_limit_config(
    document: Option<&ConnectionRateLimitJson>,
) -> ConnectionRateLimitConfig {
    let Some(document) = document else {
        return ConnectionRateLimitConfig::default();
    };
    ConnectionRateLimitConfig {
        enabled: document.enabled,
        rate: document.rate,
        burst: document.burst,
    }
    .normalized()
}

fn privacy_policy(document: &PrivacyJson) -> PrivacyPolicy {
    let mut blocked_qtypes: Vec<u16> = document
        .block_record_types
        .iter()
        .filter_map(|name| match name.trim().to_ascii_uppercase().as_str() {
            "HTTPS" | "TYPE65" => Some(65),
            "SVCB" | "TYPE64" => Some(64),
            _ => None,
        })
        .collect();
    blocked_qtypes.sort_unstable();
    blocked_qtypes.dedup();
    PrivacyPolicy {
        blocked_qtypes,
        rebinding_protection: document.rebinding_protection,
    }
}

fn rate_limit_config(document: &RateLimitJson) -> diting_ratelimit_core::Config {
    diting_ratelimit_core::Config {
        enabled: document.enabled,
        rate: document.rate as f64,
        burst: document.burst,
        ipv4_prefix: document.ipv4_prefix,
        ipv6_prefix: document.ipv6_prefix,
        exempt: document.exempt.clone(),
    }
}

fn cache_config(document: &CacheJson) -> CacheConfig {
    let percent = if document.ttl_scale_percent > 0 {
        document
            .ttl_scale_percent
            .clamp(MIN_TTL_SCALE_PERCENT, MAX_TTL_SCALE_PERCENT)
    } else {
        DEFAULT_TTL_SCALE_PERCENT
    };
    let max_ttl_seconds = if document.max_ttl_seconds > 0 {
        document.max_ttl_seconds.min(MAX_TTL_SECONDS)
    } else {
        MAX_TTL_SECONDS
    };
    CacheConfig {
        enabled: document.enabled,
        mode: TtlMode::Scale,
        ttl_scale_percent: percent,
        max_ttl_seconds,
        fixed_ttl_seconds: 0,
        min_ttl_enabled: false,
        min_ttl_seconds: 0,
        stale_fallback_enabled: document.stale_fallback_enabled,
        stale_fallback_seconds: document.stale_fallback_seconds,
        negative_ttl_enabled: document.negative_ttl_enabled,
        negative_ttl_seconds: document.negative_ttl_seconds,
    }
    .normalized()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(mode: &str, protocol: &str, server: &str) -> String {
        format!(
            r#"{{"mode":"{mode}","providers":[{{"id":"p1","protocol":"{protocol}","server":"{server}","url":"","weight":1}}],"blockResponse":"NXDOMAIN","dynamicResponse":{{"enabled":false,"requestThreshold":0,"windowSeconds":0,"nxDomainDurationSeconds":0}},"cache":{{"enabled":true,"ttlScalePercent":150,"maxTtlSeconds":600}},"bootstrap":{{"enabled":false,"ips":[]}}}}"#
        )
    }

    #[test]
    fn decodes_and_normalizes_a_plain_config() {
        let config = DnsConfig::from_json(&payload("single", "PLAIN", "8.8.8.8:53")).expect("ok");
        assert_eq!(config.mode, "single");
        assert_eq!(config.providers.len(), 1);
        assert_eq!(config.providers[0].protocol, Protocol::Plain);
        assert_eq!(config.providers[0].server, "8.8.8.8:53");
        assert_eq!(config.block_response, 1, "NXDOMAIN");
        assert!(config.cache.enabled);
        assert_eq!(config.cache.max_ttl_seconds, 600);
        assert_eq!(config.cache.mode, TtlMode::Scale);
        assert_eq!(config.cache.ttl_scale_percent, 150);
        assert_eq!(config.cache.effective_ttl(300), 450);
    }

    #[test]
    fn rejects_unknown_fields_like_disallow_unknown_fields() {
        let bad = payload("single", "PLAIN", "8.8.8.8:53")
            .replace("\"weight\":1", "\"weight\":1,\"extra\":true");
        let error = DnsConfig::from_json(&bad).expect_err("unknown field");
        assert!(
            matches!(&error, EngineError::ConfigParse(message) if message.starts_with("parse DNS config: ")),
            "{error}"
        );
    }

    #[test]
    fn rejects_trailing_data() {
        let mut text = payload("single", "PLAIN", "8.8.8.8:53");
        text.push_str("{}");
        let error = DnsConfig::from_json(&text).expect_err("trailing data");
        assert_eq!(error.to_string(), "parse DNS config: trailing data");
    }

    #[test]
    fn reports_the_kernel_error_unchanged() {
        let error =
            DnsConfig::from_json(&payload("bogus", "PLAIN", "8.8.8.8:53")).expect_err("bad mode");
        assert!(matches!(error, EngineError::ConfigInvalid(_)), "{error}");

        let error = DnsConfig::from_json(&payload("single", "PLAIN", "8.8.8.8")).expect_err("port");
        assert!(error.to_string().starts_with("provider 0:"), "{error}");
    }

    #[test]
    fn missing_collections_default_to_empty() {
        let document = DnsConfig::parse(r#"{"mode":"single"}"#).expect("decodes");
        assert!(document.providers.is_empty());
        assert_eq!(document.cache.ttl_scale_percent, 0);
        assert!(!document.bootstrap.enabled);
        assert!(document.privacy.block_record_types.is_empty());
        assert!(!document.dns64.enabled);
    }

    #[test]
    fn decodes_the_dns64_switch() {
        let json = r#"{"mode":"single","providers":[{"id":"p1","protocol":"PLAIN","server":"8.8.8.8:53","url":"","weight":1}],"blockResponse":"NXDOMAIN","dns64":{"enabled":true}}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert!(config.dns64);
    }

    #[test]
    fn decodes_the_rate_limit_block() {
        let json = r#"{"mode":"single","providers":[{"id":"p1","protocol":"PLAIN","server":"8.8.8.8:53","url":"","weight":1}],"blockResponse":"NXDOMAIN","rateLimit":{"enabled":true,"rate":20,"burst":40,"ipv4Prefix":24,"ipv6Prefix":56,"exempt":["192.168.0.1"]}}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert!(config.rate_limit.enabled);
        assert_eq!(config.rate_limit.rate, 20.0);
        assert_eq!(config.rate_limit.burst, 40);
        assert_eq!(config.rate_limit.ipv4_prefix, 24);
        assert_eq!(config.rate_limit.exempt, vec!["192.168.0.1".to_string()]);
    }

    #[test]
    fn connection_rate_limit_is_optional_and_normalized() {
        let missing =
            DnsConfig::from_json(&payload("single", "PLAIN", "8.8.8.8:53")).expect("old payload");
        assert!(!missing.connection_rate_limit.enabled);
        assert_eq!(missing.connection_rate_limit.rate, 50);
        assert_eq!(missing.connection_rate_limit.burst, 100);

        let json = r#"{"mode":"single","providers":[{"id":"p1","protocol":"PLAIN","server":"8.8.8.8:53","url":"","weight":1}],"blockResponse":"NXDOMAIN","connectionRateLimit":{"enabled":true,"rate":2000,"burst":1}}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert!(config.connection_rate_limit.enabled);
        assert_eq!(config.connection_rate_limit.rate, 1000);
        assert_eq!(config.connection_rate_limit.burst, 10);
    }

    #[test]
    fn maps_privacy_record_types_onto_qtypes() {
        let json = r#"{"mode":"single","providers":[{"id":"p1","protocol":"PLAIN","server":"8.8.8.8:53","url":"","weight":1}],"blockResponse":"NXDOMAIN","privacy":{"blockRecordTypes":["HTTPS","svcb","bogus"],"rebindingProtection":true}}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert_eq!(config.privacy.blocked_qtypes, vec![64, 65]);
        assert!(config.privacy.rebinding_protection);
    }

    #[test]
    fn drops_doq_providers_and_records_them() {
        let json = r#"{"mode":"primary_backup","providers":[{"id":"keep","protocol":"PLAIN","server":"8.8.8.8:53","url":"","weight":1},{"id":"gone","protocol":"DOQ","server":"","url":"quic://dns.example:853","weight":1}],"blockResponse":"NXDOMAIN"}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert_eq!(config.providers.len(), 1);
        assert_eq!(config.providers[0].id, "keep");
        assert_eq!(config.skipped.len(), 1);
        assert!(config.skipped[0].contains("gone"), "{:?}", config.skipped);
    }

    #[test]
    fn doh3_providers_downgrade_to_doh() {
        let json = r#"{"mode":"single","providers":[{"id":"p1","protocol":"DOH3","server":"","url":"https://dns.example/dns-query","weight":1}],"blockResponse":"NXDOMAIN"}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert_eq!(config.providers[0].protocol, Protocol::Doh);
        assert!(config.skipped.is_empty());
    }
}

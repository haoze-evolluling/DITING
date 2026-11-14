//! The `ApplyDNSConfig` payload: its JSON model, its normalization and the cache policy mapping.
//!
//! Go decoded the document with `encoding/json` + `DisallowUnknownFields`, then handed the mode,
//! the block response, the dynamic-block block and the provider list to
//! `diting_config_core`'s `normalize`, and finally mapped the cache block onto the cache kernel's
//! policy. The same three steps happen here, in the same order and with the same error texts:
//!
//! * [`DnsConfigJson`] is the document. Every field defaults (Go's zero values) and unknown fields
//!   are rejected (Go's `DisallowUnknownFields`), including inside `bootstrap` and `cache`.
//! * [`DnsConfig::parse`] reports the decode failure as `parse DNS config: …` and a trailing
//!   document as `parse DNS config: trailing data`, exactly like the two decode calls did.
//! * [`DnsConfig::normalize`] returns the kernel's first error unchanged: the mode, the provider
//!   count and each provider are checked in that order.
//!
//! `bootstrap` is decoded and carried but not used yet: stage 1 only speaks plain UDP, which needs
//! no name resolution for the endpoint. Stage 2 wires it into the DoH/DoT/DoQ dialer.

use serde::Deserialize;

use diting_config_core::dns_config::{normalize, NormalizedProvider, Provider as ConfigProvider};
use diting_config_core::dynamic::DynamicBlock;
use diting_config_core::protocol::Protocol;
use diting_dns_cache_core::policy::{Config as CacheConfig, TtlMode};
use diting_dns_core::block::BlockConfig;

use crate::error::{EngineError, EngineResult};

/// One provider entry of the payload.
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
}

/// `dynamicBlockConfig`.
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

/// `dnsCacheConfig`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CacheJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub max_ttl_seconds: i64,
    #[serde(default)]
    pub fixed_ttl_seconds: i64,
    #[serde(default)]
    pub min_ttl_enabled: bool,
    #[serde(default)]
    pub min_ttl_seconds: i64,
    #[serde(default)]
    pub stale_fallback_enabled: bool,
    #[serde(default)]
    pub stale_fallback_seconds: i64,
    #[serde(default)]
    pub negative_ttl_enabled: bool,
    #[serde(default)]
    pub negative_ttl_seconds: i64,
}

/// `bootstrapIPConfig`.
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

/// `privacy` block (U10): the privacy suite carried in the DNS document.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrivacyJson {
    #[serde(default)]
    pub block_record_types: Vec<String>,
    #[serde(default)]
    pub rebinding_protection: bool,
}

/// `bootstrapConfig`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BootstrapJson {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub ips: Vec<BootstrapIpJson>,
}

/// `dnsEngineConfig`.
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
    pub race_max_parallel: Option<i64>,
}

/// One provider after normalization.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub id: String,
    pub protocol: Protocol,
    pub server: String,
    pub url: String,
    pub weight: i64,
}

impl From<&NormalizedProvider> for Provider {
    fn from(provider: &NormalizedProvider) -> Self {
        Self {
            id: provider.id.clone(),
            protocol: provider.protocol,
            server: provider.server.clone(),
            url: provider.url.clone(),
            weight: provider.weight,
        }
    }
}

/// The published DNS configuration: what `ApplyDNSConfig` leaves behind for the query path.
#[derive(Debug, Clone)]
pub struct DnsConfig {
    pub mode: &'static str,
    pub providers: Vec<Provider>,
    /// The `ResponseType` code the block path answers with (`diting_config_core`'s table).
    pub block_response: u32,
    pub dynamic_response: BlockConfig,
    pub cache: CacheConfig,
    pub bootstrap: BootstrapJson,
    /// U10: which query types to suppress and whether to reject private-address answers.
    pub privacy: PrivacyPolicy,
    /// `raceMaxParallel`, zero when the payload did not set it.
    pub race_max_parallel: i64,
}

/// The privacy suite after mapping the document's record-type names onto qtypes.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PrivacyPolicy {
    /// Query types answered with an empty NOERROR (`HTTPS`=65, `SVCB`=64).
    pub blocked_qtypes: Vec<u16>,
    pub rebinding_protection: bool,
}

impl DnsConfig {
    /// Decodes the payload. The decode errors keep the `parse DNS config: ` prefix the Go side used,
    /// so `RuntimeDnsConfig` shows the same hint in the settings tile.
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

    /// `ApplyDNSConfig`: decode, normalize, and map the cache block.
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

        let incoming: Vec<ConfigProvider> = document
            .providers
            .iter()
            .map(|provider| ConfigProvider {
                id: provider.id.clone(),
                protocol: provider.protocol.clone(),
                server: provider.server.clone(),
                url: provider.url.clone(),
                weight: provider.weight,
            })
            .collect();

        let normalized = normalize(&document.mode, &document.block_response, dynamic, &incoming)
            .map_err(EngineError::config_invalid)?;

        Ok(DnsConfig {
            mode: normalized.mode,
            providers: normalized.providers.iter().map(Provider::from).collect(),
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
            race_max_parallel: document.race_max_parallel.unwrap_or(0),
        })
    }
}

/// Maps the document's record-type names onto qtypes, dropping anything else. Names are the ones
/// the config kernel writes (`HTTPS` / `SVCB`); numeric spellings are accepted for robustness.
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

/// Maps `dnsCacheConfig` onto the cache kernel's policy. The TTL mode is parsed by the kernel, so an
/// unknown spelling keeps the historical default instead of failing the whole config.
fn cache_config(document: &CacheJson) -> CacheConfig {
    CacheConfig {
        enabled: document.enabled,
        mode: TtlMode::parse(document.mode.as_bytes()),
        max_ttl_seconds: document.max_ttl_seconds,
        fixed_ttl_seconds: document.fixed_ttl_seconds,
        min_ttl_enabled: document.min_ttl_enabled,
        min_ttl_seconds: document.min_ttl_seconds,
        stale_fallback_enabled: document.stale_fallback_enabled,
        stale_fallback_seconds: document.stale_fallback_seconds,
        negative_ttl_enabled: document.negative_ttl_enabled,
        negative_ttl_seconds: document.negative_ttl_seconds,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(mode: &str, protocol: &str, server: &str) -> String {
        format!(
            r#"{{"mode":"{mode}","providers":[{{"id":"p1","protocol":"{protocol}","server":"{server}","url":"","weight":1}}],"blockResponse":"NXDOMAIN","dynamicResponse":{{"enabled":false,"requestThreshold":0,"windowSeconds":0,"nxDomainDurationSeconds":0}},"cache":{{"enabled":true,"mode":"limit_max_ttl","maxTtlSeconds":600}},"bootstrap":{{"enabled":false,"ips":[]}}}}"#
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
        assert_eq!(config.cache.mode, TtlMode::LimitMaxTtl);
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
        assert!(document.cache.mode.is_empty());
        assert!(!document.bootstrap.enabled);
        assert!(document.privacy.block_record_types.is_empty());
    }

    #[test]
    fn maps_privacy_record_types_onto_qtypes() {
        let json = r#"{"mode":"single","providers":[{"id":"p1","protocol":"PLAIN","server":"8.8.8.8:53","url":"","weight":1}],"blockResponse":"NXDOMAIN","privacy":{"blockRecordTypes":["HTTPS","svcb","bogus"],"rebindingProtection":true}}"#;
        let config = DnsConfig::from_json(json).expect("ok");
        assert_eq!(config.privacy.blocked_qtypes, vec![64, 65]);
        assert!(config.privacy.rebinding_protection);
    }
}

use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::{BootstrapConfig, ProviderConfig, ResolverConfig};
use diting_desktop_core::resolver::{DesktopResolver, ProviderSettings, ResolverSettings};

use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureUpstreamRequest {
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub providers: Option<Vec<ProviderConfig>>,
    #[serde(default)]
    pub bootstrap: Option<BootstrapConfig>,
    #[serde(default)]
    pub conditional_routes: Option<HashMap<String, String>>,
    #[serde(default)]
    pub fallback_providers: Option<Vec<ProviderConfig>>,
    #[serde(default)]
    pub fallback_timeout_ms: Option<i32>,
    #[serde(default)]
    pub fallback_on_rcode: Option<Vec<i32>>,
    #[serde(default)]
    pub fallback_on_error: Option<bool>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureBootstrapRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub servers: Vec<diting_desktop_api::config::BootstrapServer>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TestUpstreamRequest {
    #[serde(default)]
    pub protocol: String,
    #[serde(default)]
    pub server: String,
    #[serde(default)]
    pub url: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TestUpstreamResponse {
    pub success: bool,
    pub latency_ms: f64,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error: String,
}

fn valid_mode(mode: &str) -> bool {
    matches!(
        mode,
        "single" | "primary_backup" | "parallel_race" | "smart_prediction"
    )
}

fn normalize_route_suffix(pattern: &str) -> String {
    pattern
        .trim()
        .trim_start_matches('*')
        .trim_matches('.')
        .to_ascii_lowercase()
}

fn validate_conditional_routes(
    routes: HashMap<String, String>,
) -> Result<HashMap<String, String>, String> {
    let mut out = HashMap::with_capacity(routes.len());
    for (pattern, upstream) in routes {
        let suffix = normalize_route_suffix(&pattern);
        if suffix.is_empty() {
            return Err("条件分流的匹配域名不能为空".to_string());
        }
        if suffix.contains('/')
            || suffix.contains(':')
            || suffix.contains('*')
            || suffix.chars().any(char::is_whitespace)
        {
            return Err(format!("条件分流匹配域名不合法: {pattern}"));
        }
        let upstream = upstream.trim();
        if upstream.is_empty() {
            return Err(format!("条件分流 {suffix} 缺少目标 DNS 地址"));
        }
        if upstream.starts_with("quic://") || upstream.starts_with("doq://") {
            return Err(format!("条件分流 {suffix} 不支持 DoQ 目标"));
        }
        if out.insert(suffix.clone(), upstream.to_string()).is_some() {
            return Err(format!("条件分流匹配域名重复: {suffix}"));
        }
    }
    Ok(out)
}

fn validate_providers(
    providers: &[ProviderConfig],
    seen: &mut std::collections::HashSet<String>,
    prefix: &str,
    allow_empty: bool,
) -> Result<Vec<ProviderConfig>, String> {
    if providers.is_empty() {
        if allow_empty {
            return Ok(Vec::new());
        }
        return Err("至少需要配置一个上游 DNS 服务器".to_string());
    }
    let mut out = Vec::with_capacity(providers.len());
    for provider in providers {
        let id = provider.id.trim().to_string();
        if id.is_empty() {
            return Err(format!("{prefix}上游名称不能为空"));
        }
        if !seen.insert(id.clone()) {
            return Err(format!("上游名称重复: {id}"));
        }
        let protocol = provider.protocol.trim().to_ascii_uppercase();
        let protocol = match protocol.as_str() {
            "PLAIN" | "DOH" | "DOT" => protocol,
            "DOH3" | "H3" => "DOH".to_string(),
            "DOQ" | "QUIC" => {
                eprintln!("[{prefix}] 已忽略不再支持的 DoQ 项: {id}");
                continue;
            }
            _ => return Err(format!("不支持的上游协议: {}", provider.protocol)),
        };
        let server = provider.server.trim().to_string();
        let url = provider.url.trim().to_string();
        if server.is_empty() && url.is_empty() {
            return Err(format!("{prefix}上游 {id} 缺少服务器地址"));
        }
        let mut next = provider.clone();
        next.id = id;
        next.protocol = protocol;
        next.server = server;
        next.url = url;
        out.push(next);
    }
    Ok(out)
}

impl AppRuntime {
    pub fn upstream_config(&self) -> ResolverConfig {
        self.config().upstream
    }

    pub fn configure_upstream(
        &self,
        request: ConfigureUpstreamRequest,
    ) -> Result<(), ControllerError> {
        let has_field = !request.mode.is_empty()
            || request.providers.is_some()
            || request.bootstrap.is_some()
            || request.conditional_routes.is_some()
            || request.fallback_providers.is_some()
            || request.fallback_timeout_ms.is_some()
            || request.fallback_on_rcode.is_some()
            || request.fallback_on_error.is_some();
        if !has_field {
            return Err(ControllerError::new("未包含任何有效的上游配置项"));
        }

        self.with_config_update(|config| {
            let mut upstream = config.upstream.clone();

            if !request.mode.is_empty() {
                if !valid_mode(&request.mode) {
                    return Err(format!("不支持的上游调度模式: {}", request.mode));
                }
                upstream.mode = request.mode;
            }

            let mut seen = std::collections::HashSet::new();
            if let Some(providers) = request.providers {
                upstream.providers = validate_providers(&providers, &mut seen, "", false)?;
            } else {
                for provider in &upstream.providers {
                    seen.insert(provider.id.trim().to_string());
                }
            }

            if let Some(providers) = request.fallback_providers {
                let validated = validate_providers(&providers, &mut seen, "回退", true)?;
                upstream.fallback_providers = validated;
            }
            if let Some(timeout) = request.fallback_timeout_ms {
                upstream.fallback_timeout_ms = timeout;
            }
            if let Some(rcodes) = request.fallback_on_rcode {
                upstream.fallback_on_rcode = Some(rcodes);
            }
            if let Some(on_error) = request.fallback_on_error {
                upstream.fallback_on_error = Some(on_error);
            }
            if let Some(bootstrap) = request.bootstrap {
                if bootstrap.enabled && bootstrap.servers.is_empty() {
                    return Err("Bootstrap DNS 服务器列表不能为空".to_string());
                }
                upstream.bootstrap = bootstrap;
            }
            if let Some(routes) = request.conditional_routes {
                upstream.conditional_routes = validate_conditional_routes(routes)?;
            }

            upstream.normalize();
            config.upstream = upstream;
            config.normalize();
            Ok(())
        })
        .map_err(ControllerError::new)
    }

    pub fn configure_bootstrap(
        &self,
        request: ConfigureBootstrapRequest,
    ) -> Result<(), ControllerError> {
        let enabled = request.enabled.unwrap_or(true);
        if enabled && request.servers.is_empty() {
            return Err(ControllerError::new("Bootstrap DNS 服务器列表不能为空"));
        }
        self.update_config(|config| {
            config.upstream.bootstrap = BootstrapConfig {
                enabled,
                servers: request.servers,
            };
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub async fn test_upstream(&self, request: TestUpstreamRequest) -> TestUpstreamResponse {
        let target = if !request.server.trim().is_empty() {
            request.server.trim().to_string()
        } else {
            request.url.trim().to_string()
        };
        if target.is_empty() {
            return failed("未指定服务器地址".to_string(), 0.0);
        }
        let protocol = if request.protocol.trim().is_empty() {
            "PLAIN".to_string()
        } else {
            request.protocol.trim().to_ascii_uppercase()
        };
        let provider = match probe_provider(protocol.as_str(), target.as_str(), request.url.trim())
        {
            Ok(provider) => provider,
            Err(error) => return failed(error, 0.0),
        };

        let resolver = DesktopResolver::new();
        resolver.configure(
            &ResolverSettings {
                mode: "single".to_string(),
                providers: vec![provider],
                ..ResolverSettings::default()
            },
            &[],
        );
        if resolver.current().provider_count() == 0 {
            return failed(format!("{protocol} 地址无效，无法建立上游连接"), 0.0);
        }

        let query = plain_query("dns.alidns.com", 1);
        let started = Instant::now();
        let result =
            tokio::time::timeout(Duration::from_secs(3), resolver.resolve(&query, "")).await;
        let latency = started.elapsed().as_secs_f64() * 1000.0;
        drop(resolver);
        match result {
            Ok(Ok(_)) => TestUpstreamResponse {
                success: true,
                latency_ms: latency,
                error: String::new(),
            },
            Ok(Err(error)) => failed(error, latency),
            Err(_) => failed("请求超时".to_string(), latency),
        }
    }
}

fn failed(message: impl Into<String>, latency_ms: f64) -> TestUpstreamResponse {
    TestUpstreamResponse {
        success: false,
        latency_ms,
        error: message.into(),
    }
}

fn probe_provider(protocol: &str, target: &str, url: &str) -> Result<ProviderSettings, String> {
    let provider = ProviderSettings {
        id: "upstream-test".to_string(),
        protocol: protocol.to_string(),
        weight: 1,
        ..ProviderSettings::default()
    };
    match protocol {
        "PLAIN" => Ok(ProviderSettings {
            server: with_default_port(target, 53),
            ..provider
        }),
        "DOT" => Ok(ProviderSettings {
            server: with_default_port(target, 853),
            ..provider
        }),
        "DOH" => Ok(ProviderSettings {
            url: doh_url(target, url),
            ..provider
        }),
        other => Err(format!("不支持的上游协议: {other}")),
    }
}

fn with_default_port(target: &str, port: u16) -> String {
    let trimmed = target.trim();
    let bracketed = trimmed.starts_with('[');
    let has_port = if bracketed {
        trimmed.contains("]:")
    } else {
        trimmed
            .rsplit_once(':')
            .map(|(host, value)| {
                !host.is_empty()
                    && !host.contains(':')
                    && !value.is_empty()
                    && value.chars().all(|character| character.is_ascii_digit())
            })
            .unwrap_or(false)
    };
    if has_port {
        trimmed.to_string()
    } else if trimmed.contains(':') {
        format!("[{trimmed}]:{port}")
    } else {
        format!("{trimmed}:{port}")
    }
}

fn doh_url(target: &str, url: &str) -> String {
    let mut value = if !url.is_empty() {
        url.to_string()
    } else if target.starts_with("http://") || target.starts_with("https://") {
        target.to_string()
    } else {
        format!("https://{target}")
    };
    if !value.contains("/dns-query") {
        value = format!("{}/dns-query", value.trim_end_matches('/'));
    }
    value
}

fn plain_query(name: &str, qtype: u16) -> Vec<u8> {
    let id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| (duration.subsec_nanos() & 0xffff) as u16)
        .unwrap_or(1);
    let mut out = Vec::with_capacity(64);
    out.extend_from_slice(&id.to_be_bytes());
    out.extend_from_slice(&0x0100u16.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    for label in name.trim_end_matches('.').split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out.extend_from_slice(&qtype.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn conditional_routes_are_normalized() {
        let mut routes = HashMap::new();
        routes.insert("*.Internal.".to_string(), " tls://192.168.1.1 ".to_string());
        let out = validate_conditional_routes(routes).unwrap();
        assert_eq!(
            out.get("internal").map(String::as_str),
            Some("tls://192.168.1.1")
        );
    }

    #[test]
    fn conditional_routes_reject_invalid_entries() {
        let mut duplicated = HashMap::new();
        duplicated.insert("*.internal".to_string(), "1.1.1.1:53".to_string());
        duplicated.insert("internal".to_string(), "8.8.8.8:53".to_string());
        assert!(validate_conditional_routes(duplicated).is_err());

        let mut doq = HashMap::new();
        doq.insert("internal".to_string(), "quic://1.1.1.1".to_string());
        assert!(validate_conditional_routes(doq).is_err());

        let mut blank = HashMap::new();
        blank.insert(" ".to_string(), "1.1.1.1:53".to_string());
        assert!(validate_conditional_routes(blank).is_err());
    }

    #[test]
    fn probe_endpoints_get_their_default_ports() {
        let plain = probe_provider("PLAIN", "1.1.1.1", "").unwrap();
        assert_eq!(plain.server, "1.1.1.1:53");
        let dot = probe_provider("DOT", "dns.alidns.com", "").unwrap();
        assert_eq!(dot.server, "dns.alidns.com:853");
        assert_eq!(with_default_port("1.1.1.1:5353", 53), "1.1.1.1:5353");
        assert_eq!(with_default_port("::1", 53), "[::1]:53");
    }

    #[test]
    fn doh_urls_always_carry_the_query_path() {
        assert_eq!(
            doh_url("dns.alidns.com", ""),
            "https://dns.alidns.com/dns-query"
        );
        assert_eq!(
            doh_url("https://dns.alidns.com", ""),
            "https://dns.alidns.com/dns-query"
        );
        assert_eq!(
            doh_url("ignored", "https://example.com/resolve"),
            "https://example.com/resolve/dns-query"
        );
        assert_eq!(
            doh_url("ignored", "https://example.com/dns-query"),
            "https://example.com/dns-query"
        );
    }
}

//! Upstream resolver configuration, bootstrap and reachability test.

use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use tokio::net::UdpSocket;

use diting_desktop_api::config::{BootstrapConfig, ProviderConfig, ResolverConfig};

use crate::controller::ControllerError;
use crate::AppRuntime;

/// `ipc.ConfigureUpstreamRequest`.
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

/// `ipc.ConfigureBootstrapRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureBootstrapRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub servers: Vec<diting_desktop_api::config::BootstrapServer>,
}

/// `ipc.TestUpstreamRequest`.
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

/// `ipc.TestUpstreamResponse`.
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
        if !matches!(protocol.as_str(), "PLAIN" | "DOH" | "DOT" | "DOQ" | "DOH3") {
            return Err(format!("不支持的上游协议: {}", provider.protocol));
        }
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
    /// `GetUpstreamConfig`.
    pub fn upstream_config(&self) -> ResolverConfig {
        self.config().upstream
    }

    /// `ConfigureUpstream`.
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

        let mut config = self.config();
        let mut upstream = config.upstream.clone();

        if !request.mode.is_empty() {
            if !valid_mode(&request.mode) {
                return Err(ControllerError::new(format!(
                    "不支持的上游调度模式: {}",
                    request.mode
                )));
            }
            upstream.mode = request.mode;
        }

        let mut seen = std::collections::HashSet::new();
        if let Some(providers) = request.providers {
            upstream.providers = validate_providers(&providers, &mut seen, "", false)
                .map_err(ControllerError::new)?;
        } else {
            for provider in &upstream.providers {
                seen.insert(provider.id.trim().to_string());
            }
        }

        if let Some(providers) = request.fallback_providers {
            let validated = validate_providers(&providers, &mut seen, "回退", true)
                .map_err(ControllerError::new)?;
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
                return Err(ControllerError::new("Bootstrap DNS 服务器列表不能为空"));
            }
            upstream.bootstrap = bootstrap;
        }
        if let Some(routes) = request.conditional_routes {
            upstream.conditional_routes = routes;
        }

        upstream.normalize();
        config.upstream = upstream;
        config.normalize();
        self.apply_config(config.clone());
        self.persist_config().map_err(ControllerError::new)
    }

    /// `ConfigureBootstrap`.
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

    /// `TestUpstream`.
    ///
    /// Only plain UDP is implemented in the Rust backend; encrypted transports return a clear
    /// error instead of a fabricated latency.
    pub async fn test_upstream(&self, request: TestUpstreamRequest) -> TestUpstreamResponse {
        let target = if !request.server.trim().is_empty() {
            request.server.trim().to_string()
        } else {
            request.url.trim().to_string()
        };
        if target.is_empty() {
            return TestUpstreamResponse {
                success: false,
                error: "未指定服务器地址".to_string(),
                ..TestUpstreamResponse::default()
            };
        }
        let protocol = if request.protocol.trim().is_empty() {
            "PLAIN".to_string()
        } else {
            request.protocol.trim().to_ascii_uppercase()
        };
        if protocol != "PLAIN" {
            return TestUpstreamResponse {
                success: false,
                error: format!("当前 Rust 后端仅支持 PLAIN 上游连通性测试，{protocol} 暂未实现"),
                ..TestUpstreamResponse::default()
            };
        }

        let address = if target.contains(':') {
            target.clone()
        } else {
            format!("{target}:53")
        };
        let query = plain_query("dns.alidns.com", 1);
        let started = Instant::now();
        let result =
            tokio::time::timeout(Duration::from_secs(3), udp_exchange(&address, &query)).await;
        let latency = started.elapsed().as_secs_f64() * 1000.0;
        match result {
            Ok(Ok(())) => TestUpstreamResponse {
                success: true,
                latency_ms: latency,
                error: String::new(),
            },
            Ok(Err(error)) => TestUpstreamResponse {
                success: false,
                latency_ms: latency,
                error,
            },
            Err(_) => TestUpstreamResponse {
                success: false,
                latency_ms: latency,
                error: "请求超时".to_string(),
            },
        }
    }
}

async fn udp_exchange(address: &str, query: &[u8]) -> Result<(), String> {
    let target = tokio::net::lookup_host(address)
        .await
        .map_err(|error| error.to_string())?
        .next()
        .ok_or_else(|| "无法解析服务地址".to_string())?;
    let bind = if target.is_ipv4() {
        "0.0.0.0:0"
    } else {
        "[::]:0"
    };
    let socket = UdpSocket::bind(bind)
        .await
        .map_err(|error| error.to_string())?;
    socket
        .send_to(query, target)
        .await
        .map_err(|error| error.to_string())?;
    let mut buffer = [0u8; 4096];
    let (len, _) = socket
        .recv_from(&mut buffer)
        .await
        .map_err(|error| error.to_string())?;
    if len < 12 {
        return Err("DNS 应答长度异常".to_string());
    }
    Ok(())
}

/// Builds a minimal single-question DNS query.
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

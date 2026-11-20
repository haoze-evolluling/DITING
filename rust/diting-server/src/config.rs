//! The public server configuration and its desktop-runtime conversion.

use std::collections::HashSet;
use std::path::Path;

use diting_desktop_api::config::filter::is_valid_block_mode;
use diting_desktop_api::config::{
    BootstrapConfig, BootstrapServer, CacheConfig, Config as DesktopConfig, FilterConfig,
    ProviderConfig, QueryLogConfig, ResolverConfig,
};
use serde::{Deserialize, Serialize};

use crate::paths::ServerPaths;

/// Effective listener information. The port is chosen by the process identity, never by the UI.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ListenConfig {
    pub port: u16,
    pub bind_address: String,
    pub root: bool,
    pub lan: bool,
}

impl Default for ListenConfig {
    fn default() -> Self {
        Self {
            port: 1053,
            bind_address: "0.0.0.0".to_string(),
            root: false,
            lan: true,
        }
    }
}

/// `config.json` for server mode. It is intentionally smaller than the desktop configuration:
/// listener identity, upstream, filtering, cache and query history are the whole management
/// surface in the first release.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ServerConfig {
    pub listen: ListenConfig,
    pub upstream: ResolverConfig,
    #[serde(default = "default_filter_config")]
    pub filter: FilterConfig,
    pub cache: CacheConfig,
    #[serde(rename = "queryLog", alias = "querylog")]
    pub query_log: QueryLogConfig,
}

impl Default for ServerConfig {
    fn default() -> Self {
        let mut upstream = ResolverConfig::default();
        upstream.providers = default_server_providers();
        upstream.bootstrap = BootstrapConfig {
            enabled: true,
            servers: default_server_bootstrap(),
        };
        Self {
            listen: ListenConfig::default(),
            upstream,
            filter: default_filter_config(),
            cache: CacheConfig::default(),
            query_log: QueryLogConfig::default(),
        }
    }
}

/// Server mode starts without a subscription list; desktop keeps its own default.
fn default_filter_config() -> FilterConfig {
    FilterConfig {
        lists: Vec::new(),
        ..FilterConfig::default()
    }
}

/// Match the normal mode's default pair, using the server's `PLAIN` protocol spelling.
fn default_server_providers() -> Vec<ProviderConfig> {
    vec![
        ProviderConfig {
            id: "阿里云 (DNS)".to_string(),
            protocol: "PLAIN".to_string(),
            server: "223.5.5.5:53".to_string(),
            ..ProviderConfig::default()
        },
        ProviderConfig {
            id: "腾讯云 (DNS)".to_string(),
            protocol: "PLAIN".to_string(),
            server: "119.29.29.29:53".to_string(),
            ..ProviderConfig::default()
        },
    ]
}

/// The same three presets as normal mode's default bootstrap selection.
fn default_server_bootstrap() -> Vec<BootstrapServer> {
    vec![
        BootstrapServer {
            id: "preset_volcengine".to_string(),
            name: "火山引擎".to_string(),
            address: "180.184.1.1".to_string(),
            weight: 1.0,
        },
        BootstrapServer {
            id: "preset_dnspod".to_string(),
            name: "腾讯云".to_string(),
            address: "119.29.29.29".to_string(),
            weight: 1.0,
        },
        BootstrapServer {
            id: "preset_alidns".to_string(),
            name: "阿里云".to_string(),
            address: "223.5.5.5".to_string(),
            weight: 1.0,
        },
    ]
}

impl ServerConfig {
    /// Load, normalize and bind paths to the server data root.
    pub fn load(
        paths: &ServerPaths,
        port: u16,
        root: bool,
        bind_address: &str,
    ) -> Result<Self, String> {
        let mut config = match std::fs::read(&paths.config_path) {
            Ok(bytes) => serde_json::from_slice::<Self>(&bytes)
                .map_err(|error| format!("解析服务器配置失败: {error}"))?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Self::default(),
            Err(error) => return Err(format!("读取服务器配置失败: {error}")),
        };
        config.normalize(paths, port, root, bind_address)?;
        Ok(config)
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|error| format!("创建服务器配置目录失败: {error}"))?;
        }
        let bytes = serde_json::to_vec_pretty(self)
            .map_err(|error| format!("序列化服务器配置失败: {error}"))?;
        let temporary = path.with_extension("json.tmp");
        std::fs::write(&temporary, bytes)
            .map_err(|error| format!("写入服务器配置失败: {error}"))?;
        set_private_mode(&temporary);
        if path.exists() {
            std::fs::remove_file(path).map_err(|error| format!("替换服务器配置失败: {error}"))?;
        }
        std::fs::rename(&temporary, path).map_err(|error| format!("提交服务器配置失败: {error}"))
    }

    /// Validate, repair and bind every server-owned path.
    pub fn normalize(
        &mut self,
        paths: &ServerPaths,
        port: u16,
        root: bool,
        bind_address: &str,
    ) -> Result<(), String> {
        if port == 0 {
            return Err("监听端口必须在 1–65535 之间".to_string());
        }
        self.listen = ListenConfig {
            port,
            bind_address: bind_address.trim().to_string(),
            root,
            lan: true,
        };
        if self.listen.bind_address.is_empty() {
            self.listen.bind_address = "0.0.0.0".to_string();
        }

        validate_upstream(&mut self.upstream)?;
        self.filter.normalize();
        if !is_valid_block_mode(&self.filter.block_mode) {
            return Err(format!("未知的阻断模式: {}", self.filter.block_mode));
        }
        self.filter.data_dir = paths.rules_dir.to_string_lossy().into_owned();
        self.cache.normalize();
        self.query_log.normalize();
        self.query_log.data_dir = paths.querylog_dir.to_string_lossy().into_owned();
        if self.cache.persist_enabled && self.cache.persist_path.trim().is_empty() {
            self.cache.persist_path = paths
                .data_dir
                .join("cache.json")
                .to_string_lossy()
                .into_owned();
        }
        Ok(())
    }

    /// Replace the management-editable sections while preserving the effective listener identity.
    pub fn replace_editable(&mut self, next: Self, paths: &ServerPaths) -> Result<(), String> {
        let listen = self.listen.clone();
        *self = next;
        self.listen = listen;
        self.normalize(
            paths,
            self.listen.port,
            self.listen.root,
            &self.listen.bind_address.clone(),
        )
    }

    pub fn desktop_config(&self) -> DesktopConfig {
        let mut config = DesktopConfig::default();
        let port = self.listen.port;
        let v4 = format!("{}:{port}", self.listen.bind_address);
        let v6 = format!("[::]:{port}");
        config.dns.udp_addresses = vec![v4.clone(), v6.clone()];
        config.dns.tcp_addresses = vec![v4, v6];
        config.dns.allow_lan = self.listen.lan;
        config.dns.block_private_ptr = false;
        config.upstream = self.upstream.clone();
        config.filter = self.filter.clone();
        config.cache = self.cache.clone();
        config.query_log = self.query_log.clone();
        config.encrypted.enabled = false;
        config.encrypted.dot_enabled = false;
        config.encrypted.doh_enabled = false;
        config.encrypted.doq_enabled = false;
        config.client.groups_enabled = false;
        config.client.groups.clear();
        config.web.enabled = false;
        config
    }

    /// A compact upstream summary for status cards.
    pub fn upstream_summary(&self) -> String {
        let names: Vec<&str> = self
            .upstream
            .providers
            .iter()
            .map(|provider| provider.id.as_str())
            .collect();
        if names.is_empty() {
            return "—".to_string();
        }
        names.join(" · ")
    }
}

fn validate_upstream(config: &mut ResolverConfig) -> Result<(), String> {
    const MODES: [&str; 4] = [
        "single",
        "primary_backup",
        "parallel_race",
        "smart_prediction",
    ];
    if !MODES.contains(&config.mode.trim()) {
        return Err(format!("未知的上游调度模式: {}", config.mode));
    }
    if config.providers.is_empty() {
        return Err("至少需要配置一个上游 DNS 服务".to_string());
    }
    let mut seen = HashSet::new();
    for provider in &mut config.providers {
        provider.id = provider.id.trim().to_string();
        if provider.id.is_empty() {
            return Err("上游 DNS 服务名称不能为空".to_string());
        }
        let protocol = provider.protocol.trim().to_ascii_uppercase();
        if !matches!(protocol.as_str(), "PLAIN" | "DOH" | "DOT" | "DOQ" | "DOH3") {
            return Err(format!("未知的 DNS 协议: {}", provider.protocol));
        }
        provider.protocol = protocol;
        if provider.server.trim().is_empty() && provider.url.trim().is_empty() {
            return Err(format!("上游 DNS 服务 {} 缺少地址", provider.id));
        }
        if !seen.insert(provider.id.to_lowercase()) {
            return Err(format!("上游 DNS 服务名称重复: {}", provider.id));
        }
    }
    config.normalize();
    Ok(())
}

#[cfg(unix)]
fn set_private_mode(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}

#[cfg(not(unix))]
fn set_private_mode(_path: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(tag: &str) -> ServerPaths {
        ServerPaths::new(
            std::env::temp_dir().join(format!("diting-server-config-{tag}-{}", std::process::id())),
        )
    }

    #[test]
    fn defaults_are_lan_serving_with_separate_paths() {
        let paths = paths("defaults");
        let mut config = ServerConfig::default();
        config.normalize(&paths, 53, true, "0.0.0.0").unwrap();
        assert_eq!(config.listen.port, 53);
        assert!(config.listen.root);
        assert!(config.listen.lan);
        assert_eq!(config.filter.data_dir, paths.rules_dir.to_string_lossy());
        assert_eq!(
            config.query_log.data_dir,
            paths.querylog_dir.to_string_lossy()
        );
        assert_eq!(config.query_log.retention_days, 7);
        assert_eq!(config.query_log.max_entries, 10_000);
        assert!(config.filter.lists.is_empty());
        assert_eq!(config.upstream.providers.len(), 2);
        assert_eq!(config.upstream.providers[0].protocol, "PLAIN");
        assert_eq!(config.upstream.providers[0].server, "223.5.5.5:53");
        assert_eq!(
            config
                .upstream
                .bootstrap
                .servers
                .iter()
                .map(|server| server.id.as_str())
                .collect::<Vec<_>>(),
            ["preset_volcengine", "preset_dnspod", "preset_alidns"]
        );
    }

    #[test]
    fn missing_filter_uses_the_server_default_without_subscriptions() {
        let config: ServerConfig = serde_json::from_str(
            r#"{"upstream":{"providers":[{"id":"test","protocol":"PLAIN","server":"1.1.1.1:53"}]}}"#,
        )
        .unwrap();
        assert!(config.filter.lists.is_empty());
    }

    #[test]
    fn invalid_upstream_is_rejected() {
        let paths = paths("invalid");
        let mut config = ServerConfig::default();
        config.upstream.providers.clear();
        assert!(config.normalize(&paths, 1053, false, "0.0.0.0").is_err());
        config.upstream.providers = diting_desktop_api::config::upstream::default_providers();
        config.upstream.providers[0].protocol = "HTTP".to_string();
        assert!(config.normalize(&paths, 1053, false, "0.0.0.0").is_err());
    }

    #[test]
    fn editable_replacement_keeps_listener_identity() {
        let paths = paths("replace");
        let mut current = ServerConfig::default();
        current.normalize(&paths, 1053, false, "0.0.0.0").unwrap();
        let mut next = current.clone();
        next.listen.port = 53;
        next.upstream.mode = "parallel_race".to_string();
        current.replace_editable(next, &paths).unwrap();
        assert_eq!(current.listen.port, 1053);
        assert_eq!(current.upstream.mode, "parallel_race");
    }
}

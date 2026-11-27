use std::path::Path;
use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use diting_desktop_app::{dns_server_config, AppRuntime, PlatformHandles, RuntimeStores};
use diting_desktop_core::querylog::{NameCount, SearchQuery, Summary};
use diting_desktop_dns::server::{BoundDnsSockets, DnsServer};
use serde::Serialize;
use serde_json::{json, Value};
use tokio::sync::Mutex;

use crate::config::ServerConfig;
use crate::observer::ServerQueryObserver;
use crate::paths::ServerPaths;
use crate::storage::ServerStorage;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub running: bool,
    pub port: u16,
    pub root: bool,
    pub bind_address: String,
    pub addresses: Vec<String>,
    pub started_at: i64,
    pub uptime_seconds: i64,
    pub version: String,
    pub upstream_summary: String,
    pub filter_enabled: bool,
    pub filter_rules: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Stats {
    pub summary: SummaryWithRate,
    pub per_hour: Vec<diting_desktop_core::querylog::HourPoint>,
    pub top_domains: Vec<NameCount>,
    pub top_blocked_domains: Vec<NameCount>,
    pub top_clients: Vec<NameCount>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SummaryWithRate {
    #[serde(flatten)]
    pub summary: Summary,
    pub blocked_rate: f64,
}

pub struct ServerRuntime {
    paths: ServerPaths,
    config: RwLock<ServerConfig>,
    addresses: RwLock<Vec<String>>,
    desktop: Arc<AppRuntime>,
    dns: Mutex<Option<Arc<DnsServer>>>,
    started_at_ms: i64,
    storage: Arc<ServerStorage>,
}

impl ServerRuntime {
    pub fn new(
        paths: ServerPaths,
        config: ServerConfig,
        stores: RuntimeStores,
        storage: Arc<ServerStorage>,
    ) -> Result<Self, String> {
        paths.ensure_dirs().map_err(|error| {
            format!(
                "创建服务器数据目录失败 ({}): {error}",
                paths.data_dir.display()
            )
        })?;
        let desktop_config = config.desktop_config();
        let desktop = Arc::new(AppRuntime::with_stores(
            desktop_config,
            stores,
            paths.data_dir.clone(),
            Some(PlatformHandles::default()),
        ));
        if let Err(error) = desktop.load_cache_from_store() {
            eprintln!("[缓存] 恢复缓存失败，将以空缓存启动: {error}");
        }
        desktop.set_observer(Arc::new(ServerQueryObserver::new(Arc::clone(
            &desktop.querylog,
        ))));
        Ok(Self {
            paths,
            config: RwLock::new(config),
            addresses: RwLock::new(Vec::new()),
            desktop,
            dns: Mutex::new(None),
            started_at_ms: now_ms(),
            storage,
        })
    }

    pub fn paths(&self) -> &ServerPaths {
        &self.paths
    }

    pub fn config(&self) -> ServerConfig {
        self.config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }

    pub async fn is_running(&self) -> bool {
        self.dns
            .lock()
            .await
            .as_ref()
            .is_some_and(|server| server.is_serving())
    }

    pub async fn start(&self, bound: BoundDnsSockets) -> Result<(), String> {
        let mut guard = self.dns.lock().await;
        if guard.as_ref().is_some_and(|server| server.is_serving()) {
            return Err("服务器已在运行".to_string());
        }
        let addresses = bound.addresses();
        let config = self.config();
        let server = Arc::new(DnsServer::new(
            dns_server_config(&config.desktop_config()),
            self.desktop.pipeline(),
        ));
        server.start_with_bound(bound).await?;
        *self
            .addresses
            .write()
            .unwrap_or_else(|error| error.into_inner()) = addresses;
        *guard = Some(server);
        Ok(())
    }

    pub async fn shutdown(&self) {
        let server = self.dns.lock().await.take();
        if let Some(server) = server {
            server.shutdown().await;
        }
        let _ = self.desktop.dump_cache_to_store();
        let _ = self.desktop.querylog.close();
        let _ = self.storage.checkpoint();
    }

    pub fn status(&self, running: bool) -> Status {
        let config = self.config();
        let filter = self.desktop.filter.stats();
        Status {
            running,
            port: config.listen.port,
            root: config.listen.root,
            bind_address: config.listen.bind_address.clone(),
            addresses: {
                let addresses = self
                    .addresses
                    .read()
                    .unwrap_or_else(|error| error.into_inner());
                if addresses.is_empty() {
                    vec![format!(
                        "{}:{}",
                        config.listen.bind_address, config.listen.port
                    )]
                } else {
                    addresses.clone()
                }
            },
            started_at: self.started_at_ms,
            uptime_seconds: ((now_ms() - self.started_at_ms).max(0)) / 1000,
            version: env!("CARGO_PKG_VERSION").to_string(),
            upstream_summary: config.upstream_summary(),
            filter_enabled: filter.enabled,
            filter_rules: filter.total_rules,
        }
    }

    pub fn replace_config(&self, next: ServerConfig) -> Result<ServerConfig, String> {
        let mut merged = self.config();
        merged.replace_editable(next, &self.paths)?;
        self.storage.save_config(&self.paths, &merged)?;
        self.desktop.apply_config(merged.desktop_config());
        *self
            .config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = merged.clone();
        Ok(merged)
    }

    pub fn stats(&self) -> Stats {
        let summary = self.desktop.querylog.stats();
        let blocked_rate = if summary.queries == 0 {
            0.0
        } else {
            summary.blocked as f64 / summary.queries as f64
        };
        Stats {
            summary: SummaryWithRate {
                summary,
                blocked_rate,
            },
            per_hour: self.desktop.querylog.per_hour(),
            top_domains: self.desktop.querylog.top_domains(10),
            top_blocked_domains: self.desktop.querylog.top_blocked_domains(10),
            top_clients: self.desktop.querylog.top_clients(10),
        }
    }

    pub fn query_log(&self, query: SearchQuery) -> Value {
        serde_json::to_value(self.desktop.querylog.search(query)).unwrap_or(Value::Null)
    }

    pub fn clear_query_log(&self) -> Result<Value, String> {
        self.desktop
            .querylog
            .clear(true)
            .map_err(|error| error.to_string())?;
        Ok(json!({"cleared": true}))
    }

    pub async fn refresh_filter(&self, id: &str) -> Result<ServerConfig, String> {
        let result = self.desktop.filter.refresh_lists(id).await;
        // 即使刷新失败，也要把 lastStatus / lastError 落库，界面才能显示失败原因。
        let saved = self.persist_filter_state()?;
        match result {
            Ok(()) => Ok(saved),
            Err(error) => Err(error.to_string()),
        }
    }

    /// 定时检查到期订阅；无论是否刷新到新内容，都把 `lastUpdated` 等元数据落库。
    pub async fn refresh_due_filter(&self) -> Result<bool, String> {
        let before = self.desktop.filter.config();
        let result = self
            .desktop
            .filter
            .refresh_due()
            .await
            .map_err(|error| error.to_string());
        let after = self.desktop.filter.config();
        if after != before {
            self.persist_filter_state()?;
        }
        result
    }

    fn persist_filter_state(&self) -> Result<ServerConfig, String> {
        let mut next = self.config();
        next.filter = self.desktop.filter.config();
        self.storage.save_config(&self.paths, &next)?;
        *self
            .config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = next.clone();
        Ok(next)
    }

    pub fn clear_cache(&self) -> Value {
        self.desktop.cache.clear();
        json!({"cleared": true})
    }

    pub fn filter_check(&self, domain: &str, qtype: u16) -> Value {
        let result = self.desktop.filter.check_host(domain, qtype);
        json!({
            "blocked": result.blocked,
            "action": result.action.as_str(),
            "matchedRule": result.matched_rule,
            "listName": result.list_name,
            "reason": result.reason,
        })
    }

    pub fn save_initial_config(&self) -> Result<(), String> {
        self.storage.save_config(&self.paths, &self.config())
    }

    pub fn log_path(&self) -> &Path {
        &self.paths.log_path
    }
}

pub fn parse_qtype(value: Option<&str>) -> u16 {
    match value.unwrap_or("A").trim().to_ascii_uppercase().as_str() {
        "AAAA" => 28,
        "CNAME" => 5,
        "HTTPS" => 65,
        "SVCB" => 64,
        "MX" => 15,
        "NS" => 2,
        "PTR" => 12,
        "SOA" => 6,
        "SRV" => 33,
        "TXT" => 16,
        _ => 1,
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_dns::server::{BoundDnsSockets, ServerConfig as ListenerConfig};

    fn paths(tag: &str) -> ServerPaths {
        let root = std::env::temp_dir().join(format!(
            "diting-server-runtime-{tag}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        ServerPaths::new(root)
    }

    fn runtime(tag: &str, config: ServerConfig) -> ServerRuntime {
        let paths = paths(tag);
        paths.ensure_dirs().unwrap();
        let storage = Arc::new(ServerStorage::open(&paths).unwrap());
        let stores = storage.runtime_stores(&config);
        ServerRuntime::new(paths, config, stores, storage).unwrap()
    }

    #[test]
    fn runtime_starts_with_defaults_and_rejects_an_empty_provider_list() {
        let mut config = ServerConfig::default();
        config
            .normalize(&paths("defaults"), 1053, false, "0.0.0.0")
            .unwrap();
        let runtime = runtime("defaults", config);
        let status = runtime.status(false);
        assert_eq!(status.port, 1053);
        assert!(!status.running);

        let mut next = runtime.config();
        next.upstream.providers.clear();
        assert!(runtime.replace_config(next).is_err());
    }

    #[tokio::test]
    async fn udp_server_blocks_and_records_a_lan_query() {
        let paths = paths("udp");
        let probe = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);

        let mut config = ServerConfig::default();
        config.filter.custom_rules = vec!["||ads.example.com^".to_string()];
        config.cache.enabled = false;
        config.normalize(&paths, port, false, "127.0.0.1").unwrap();
        let runtime = runtime("udp", config);
        let bound = BoundDnsSockets::bind(&ListenerConfig {
            udp_addresses: vec![format!("127.0.0.1:{port}")],
            tcp_addresses: Vec::new(),
            ..ListenerConfig::default()
        })
        .unwrap();
        runtime.start(bound).await.unwrap();

        let client = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let query = diting_dns_wire::build::MessageBuilder::query("ads.example.com", 1, 1)
            .finish()
            .unwrap();
        client
            .send_to(&query, format!("127.0.0.1:{port}"))
            .await
            .unwrap();
        let mut response = [0u8; 512];
        let (length, _) = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            client.recv_from(&mut response),
        )
        .await
        .unwrap()
        .unwrap();
        assert!(diting_dns_wire::parse_header(&response[..length])
            .unwrap()
            .is_response());

        let result = runtime.query_log(SearchQuery {
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(result["total"], 1);
        let entry = &result["entries"][0];
        assert_eq!(entry["domain"], "ads.example.com");
        assert_eq!(entry["clientIP"], "127.0.0.1");
        assert_eq!(entry["status"], "blocked");

        runtime.shutdown().await;
    }
}

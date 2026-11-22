use std::path::PathBuf;
use std::sync::{Arc, RwLock};

use diting_desktop_api::config::{store, Config};
use diting_desktop_core::access::AccessControl;
use diting_desktop_core::cache::DesktopCache;
use diting_desktop_core::cert::CertManager;
use diting_desktop_core::clients::ClientDirectory;
use diting_desktop_core::filter::{GroupConfig, RuleEngine};
use diting_desktop_core::hosts::HostsResolver;
use diting_desktop_core::metrics::MetricsTracker;
use diting_desktop_core::querylog::QueryLog;
use diting_desktop_core::ratelimit::RateLimiter;
use diting_desktop_core::resolver::DesktopResolver;
use diting_desktop_core::rewrite::RewriteEngine;
use diting_desktop_core::safebrowsing::SafeBrowsingEngine;
use diting_desktop_core::safesearch::SafeSearchEngine;
use diting_desktop_core::zone::ZoneEngine;
use diting_desktop_dns::builder::PipelineParts;
use diting_desktop_dns::encrypted::EncryptedListeners;
use diting_desktop_dns::server::{DnsServer, ServerConfig};
use diting_desktop_dns::stages::metrics::QueryObserver;
use diting_desktop_platform::paths;
use diting_desktop_platform::traits::{
    AdapterScanner, AutoStartManager, DnsManager, FirewallManager, PortChecker, ServiceManager,
    StateStore,
};
use tokio::sync::Mutex;

use crate::settings;

mod encrypted;

pub struct PlatformHandles {
    pub adapters: Option<Arc<dyn AdapterScanner>>,
    pub dns_manager: Option<Arc<dyn DnsManager>>,
    pub port_checker: Option<Arc<dyn PortChecker>>,
    pub service_manager: Option<Arc<dyn ServiceManager>>,
    pub firewall: Option<Arc<dyn FirewallManager>>,
    pub autostart: Option<Arc<dyn AutoStartManager>>,
    pub state_store: Option<Arc<dyn StateStore>>,
    pub lan_addresses: Arc<dyn Fn() -> Vec<String> + Send + Sync>,
    pub platform_name: String,
    pub firewall_backend: String,
    pub is_elevated: bool,
}

impl Default for PlatformHandles {
    fn default() -> Self {
        Self {
            adapters: None,
            dns_manager: None,
            port_checker: None,
            service_manager: None,
            firewall: None,
            autostart: None,
            state_store: None,
            lan_addresses: Arc::new(Vec::new),
            platform_name: String::new(),
            firewall_backend: "none".to_string(),
            is_elevated: false,
        }
    }
}

impl PlatformHandles {
    pub fn lan_addresses(&self) -> Vec<String> {
        (self.lan_addresses)()
    }

    pub fn empty_lan() -> Arc<dyn Fn() -> Vec<String> + Send + Sync> {
        Arc::new(Vec::new)
    }
}

pub struct AppRuntime {
    config: Arc<RwLock<Config>>,
    config_path: PathBuf,
    config_op: std::sync::Mutex<()>,
    platform: RwLock<Option<Arc<PlatformHandles>>>,
    pub resolver: Arc<DesktopResolver>,
    pub cache: Arc<DesktopCache>,
    pub filter: RuleEngine,
    pub hosts: Arc<HostsResolver>,
    pub rewrite: Arc<RewriteEngine>,
    pub zone: Arc<ZoneEngine>,
    pub safesearch: Arc<SafeSearchEngine>,
    pub safebrowsing: Arc<SafeBrowsingEngine>,
    pub clients: Arc<ClientDirectory>,
    pub access: Arc<AccessControl>,
    pub ratelimit: Arc<RateLimiter>,
    pub querylog: Arc<QueryLog>,
    pub metrics: Arc<MetricsTracker>,
    pub cert: Arc<CertManager>,
    observer: RwLock<Option<Arc<dyn QueryObserver>>>,
    dns: Mutex<Option<Arc<DnsServer>>>,
    encrypted: Arc<RwLock<Option<Arc<EncryptedListeners>>>>,
    dns_lifecycle: Mutex<()>,
}

impl AppRuntime {
    pub fn new(config: Config) -> Self {
        Self::with_paths(config, paths::default_config_path())
    }

    fn with_paths(config: Config, config_path: PathBuf) -> Self {
        let groups = GroupConfig {
            enabled: config.client.groups_enabled,
            groups: config.client.groups.clone(),
        };
        let filter = RuleEngine::new_with_groups(config.filter.clone(), groups);
        let resolver = Arc::new(DesktopResolver::new());
        resolver.configure(
            &settings::resolver_settings(&config.upstream),
            &settings::group_upstreams(&config),
        );
        let cert_dir = paths::default_cert_dir();
        Self {
            cache: Arc::new(DesktopCache::new(settings::cache_settings(&config.cache))),
            filter,
            hosts: Arc::new(HostsResolver::new(&config.hosts)),
            rewrite: Arc::new(RewriteEngine::new(&config.rewrite)),
            zone: Arc::new(ZoneEngine::new(&config.zone)),
            safesearch: Arc::new(SafeSearchEngine::new(&config.safe_search)),
            safebrowsing: Arc::new(SafeBrowsingEngine::new(config.safe_browsing.clone())),
            clients: Arc::new(ClientDirectory::new(&config.client)),
            access: Arc::new(AccessControl::new(&config.access)),
            ratelimit: Arc::new(RateLimiter::new(&config.rate_limit)),
            querylog: Arc::new(QueryLog::new(settings::querylog_settings(
                &config.query_log,
            ))),
            metrics: Arc::new(MetricsTracker::new()),
            cert: Arc::new(CertManager::new(cert_dir, config.encrypted.cert.clone())),
            observer: RwLock::new(None),
            dns: Mutex::new(None),
            encrypted: Arc::new(RwLock::new(None)),
            dns_lifecycle: Mutex::new(()),
            config_path,
            config_op: std::sync::Mutex::new(()),
            platform: RwLock::new(None),
            resolver,
            config: Arc::new(RwLock::new(config)),
        }
    }

    pub fn with_platform(config: Config, config_path: PathBuf, platform: PlatformHandles) -> Self {
        let runtime = Self::with_paths(config, config_path);
        runtime.set_platform(platform);
        runtime
    }

    pub fn set_platform(&self, platform: PlatformHandles) {
        *self
            .platform
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Some(Arc::new(platform));
    }

    pub fn platform(&self) -> Option<Arc<PlatformHandles>> {
        self.platform
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn lan_addresses(&self) -> Vec<String> {
        self.platform()
            .map(|platform| platform.lan_addresses())
            .unwrap_or_default()
    }

    pub fn config_path(&self) -> PathBuf {
        self.config_path.clone()
    }

    pub fn persist_config(&self) -> Result<(), String> {
        let config = self.config();
        store::save_config(&self.config_path, &config).map_err(|error| error.to_string())
    }

    pub fn update_config(&self, mutate: impl FnOnce(&mut Config)) -> Result<Config, String> {
        self.with_config_update(|next| {
            mutate(next);
            Ok(next.clone())
        })
    }

    pub fn update_config_in_memory(&self, mutate: impl FnOnce(&mut Config)) -> Config {
        let _op = self.lock_config_op();
        let mut next = self.config();
        mutate(&mut next);
        self.apply_config(next.clone());
        next
    }

    pub fn with_config_update<T>(
        &self,
        update: impl FnOnce(&mut Config) -> Result<T, String>,
    ) -> Result<T, String> {
        let _op = self.lock_config_op();
        let mut next = self.config();
        let outcome = update(&mut next)?;
        self.apply_config(next.clone());
        store::save_config(&self.config_path, &next).map_err(|error| error.to_string())?;
        Ok(outcome)
    }

    pub fn with_config_update_in_memory<T>(
        &self,
        update: impl FnOnce(&mut Config) -> Result<T, String>,
    ) -> Result<T, String> {
        let _op = self.lock_config_op();
        let mut next = self.config();
        let outcome = update(&mut next)?;
        self.apply_config(next.clone());
        Ok(outcome)
    }

    fn lock_config_op(&self) -> std::sync::MutexGuard<'_, ()> {
        self.config_op
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    pub fn set_observer(&self, observer: Arc<dyn QueryObserver>) {
        *self
            .observer
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Some(observer);
    }

    fn observer(&self) -> Option<Arc<dyn QueryObserver>> {
        self.observer
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn config(&self) -> Config {
        self.config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// 只读一小块配置时用它：`Config` 有二十多个子配置，每请求整份克隆代价很高。
    pub fn with_config<T>(&self, read: impl FnOnce(&Config) -> T) -> T {
        read(
            &self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner()),
        )
    }

    pub fn config_handle(&self) -> Arc<RwLock<Config>> {
        Arc::clone(&self.config)
    }

    pub fn apply_config(&self, config: Config) {
        *self
            .config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = config.clone();
        self.cache
            .configure(settings::cache_settings(&config.cache));
        self.filter.configure(config.filter.clone());
        self.filter.set_groups(GroupConfig {
            enabled: config.client.groups_enabled,
            groups: config.client.groups.clone(),
        });
        self.hosts.configure(&config.hosts);
        self.rewrite.configure(&config.rewrite);
        self.zone.configure(&config.zone);
        self.safesearch.configure(&config.safe_search);
        self.safebrowsing.configure(config.safe_browsing.clone());
        self.clients.configure(&config.client);
        self.access.configure(&config.access);
        self.ratelimit.configure(&config.rate_limit);
        self.querylog
            .configure(settings::querylog_settings(&config.query_log));
        self.cert.configure(config.encrypted.cert.clone());
        self.resolver.configure(
            &settings::resolver_settings(&config.upstream),
            &settings::group_upstreams(&config),
        );
    }

    pub fn is_dns_running(&self) -> bool {
        self.dns
            .try_lock()
            .ok()
            .and_then(|guard| guard.as_ref().map(|server| server.is_serving()))
            .unwrap_or(false)
    }

    pub async fn start_dns(&self) -> Result<(), String> {
        let _lifecycle = self.dns_lifecycle.lock().await;
        let config = self.config();
        let pipeline = self.pipeline();
        let server_config = dns_server_config(&config);
        let server = Arc::new(DnsServer::new(server_config, pipeline));
        self.stop_encrypted().await;
        let mut guard = self.dns.lock().await;
        if let Some(previous) = guard.take() {
            previous.shutdown().await;
        }
        server.start().await?;
        *guard = Some(Arc::clone(&server));
        drop(guard);
        self.set_encrypted(self.start_encrypted(&config, server).await);
        Ok(())
    }

    pub async fn stop_dns(&self) {
        let _lifecycle = self.dns_lifecycle.lock().await;
        self.stop_encrypted().await;
        let server = self.dns.lock().await.take();
        if let Some(server) = server {
            server.shutdown().await;
        }
    }

    pub fn pipeline(&self) -> Arc<diting_desktop_dns::pipeline::Pipeline> {
        PipelineParts {
            config: Arc::clone(&self.config),
            resolver: Arc::clone(&self.resolver),
            cache: Arc::clone(&self.cache),
            filter: self.filter.clone(),
            hosts: Arc::clone(&self.hosts),
            rewrite: Arc::clone(&self.rewrite),
            zone: Arc::clone(&self.zone),
            safesearch: Arc::clone(&self.safesearch),
            safebrowsing: Arc::clone(&self.safebrowsing),
            clients: Arc::clone(&self.clients),
            access: Arc::clone(&self.access),
            ratelimit: Arc::clone(&self.ratelimit),
            metrics: Arc::clone(&self.metrics),
            observer: self.observer(),
            ddr: self.ddr_provider(),
        }
        .build()
    }

    pub fn save_cache(
        &self,
    ) -> Result<Option<diting_desktop_core::cache::persist::PersistStatus>, String> {
        let config = self.config();
        if !config.cache.persist_enabled {
            return Ok(None);
        }
        let path = if config.cache.persist_path.trim().is_empty() {
            paths::default_data_dir().join("cache.json")
        } else {
            std::path::PathBuf::from(&config.cache.persist_path)
        };
        self.cache.save(&path).map(Some)
    }

    pub fn load_cache(&self) -> Result<usize, String> {
        let config = self.config();
        let path = if config.cache.persist_path.trim().is_empty() {
            paths::default_data_dir().join("cache.json")
        } else {
            std::path::PathBuf::from(&config.cache.persist_path)
        };
        self.cache.load(&path)
    }
}

pub fn dns_server_config(config: &Config) -> ServerConfig {
    ServerConfig {
        udp_addresses: config.dns.udp_addresses.clone(),
        tcp_addresses: config.dns.tcp_addresses.clone(),
        read_timeout: std::time::Duration::from_nanos(config.dns.read_timeout.0.max(0) as u64),
        write_timeout: std::time::Duration::from_nanos(config.dns.write_timeout.0.max(0) as u64),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_builds_from_defaults() {
        let runtime = AppRuntime::new(Config::default());
        assert!(!runtime.is_dns_running());
        assert!(runtime.pipeline().stage_names().contains(&"forward"));
    }

    #[test]
    fn listener_config_maps_timeouts() {
        let config = Config::default();
        let server = dns_server_config(&config);
        assert_eq!(server.udp_addresses, config.dns.udp_addresses);
        assert_eq!(server.read_timeout.as_secs(), 5);
    }
}

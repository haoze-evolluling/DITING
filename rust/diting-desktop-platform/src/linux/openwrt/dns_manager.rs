use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use diting_desktop_api::config::{
    OpenWrtConfig, OPENWRT_MODE_DNSMASQ_UPSTREAM, OPENWRT_MODE_REPLACE_DNSMASQ,
};
use diting_desktop_api::platform_types::{AdapterInfo, AdapterState, TakeoverState};
use serde::{Deserialize, Serialize};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::paths;
use crate::state::FileStateStore;
use crate::traits::{AdapterScanner, DnsManager, StateStore};

use super::super::files;
use super::firewall::OpenWrtFirewall;
use super::uci;

const BACKUP_FILE_NAME: &str = "openwrt_dnsmasq_backup.json";
const RESTORE_SCRIPT_NAME: &str = "restore-dns.sh";
const DNSMASQ_SECTION: &str = "dhcp.@dnsmasq[0]";

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DnsmasqBackup {
    pub port: Option<String>,
    pub noresolv: Option<String>,
    pub cachesize: Option<String>,
    pub servers: Vec<String>,
    pub local_domain: String,
}

#[derive(Default)]
struct RuntimeTakeover {
    active: bool,
    adapters: Vec<AdapterState>,
    local_domain: String,
}

pub struct OpenWrtDnsManager {
    executor: Arc<dyn CommandExecutor>,
    state_store: Arc<dyn StateStore>,
    firewall: Arc<OpenWrtFirewall>,
    config: Mutex<OpenWrtConfig>,
    runtime: Mutex<RuntimeTakeover>,
    backup_dir: PathBuf,
    version: String,
}

impl OpenWrtDnsManager {
    pub fn new(
        executor: Arc<dyn CommandExecutor>,
        state_store: Arc<dyn StateStore>,
        firewall: Arc<OpenWrtFirewall>,
        initial_config: OpenWrtConfig,
        version: impl Into<String>,
    ) -> Self {
        let backup_dir = state_store
            .file_path()
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .map(Path::to_path_buf)
            .unwrap_or_else(paths::default_data_dir);
        let version = version.into();
        let mut normalized = initial_config;
        normalized.normalize();
        Self {
            executor,
            state_store,
            firewall,
            config: Mutex::new(normalized),
            runtime: Mutex::new(RuntimeTakeover {
                local_domain: "lan".to_string(),
                ..RuntimeTakeover::default()
            }),
            backup_dir,
            version: if version.is_empty() {
                "dev".to_string()
            } else {
                version
            },
        }
    }

    pub fn set_openwrt_config(&self, mut next: OpenWrtConfig) {
        next.normalize();
        *self
            .config
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = next;
    }

    pub fn openwrt_config(&self) -> OpenWrtConfig {
        self.config
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    pub fn detected_local_domain(&self) -> String {
        let domain = self
            .runtime
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .local_domain
            .clone();
        if domain.is_empty() {
            "lan".to_string()
        } else {
            domain
        }
    }

    pub async fn probe_local_domain(&self) -> String {
        if let Some(backup) = self.read_backup() {
            if !backup.local_domain.is_empty() {
                return backup.local_domain;
            }
        }
        detect_uci_local_domain(self.executor.as_ref()).await
    }

    fn backup_path(&self) -> PathBuf {
        self.backup_dir.join(BACKUP_FILE_NAME)
    }

    fn restore_script_path(&self) -> PathBuf {
        self.backup_dir.join(RESTORE_SCRIPT_NAME)
    }

    pub fn read_backup(&self) -> Option<DnsmasqBackup> {
        let bytes = files::read_file_at(&self.backup_path()).ok()?;
        serde_json::from_slice(&bytes).ok()
    }

    fn write_backup(&self, backup: &DnsmasqBackup) -> PlatformResult<()> {
        let json = serde_json::to_vec_pretty(backup)
            .map_err(|error| PlatformError::message(format!("序列化 dnsmasq 备份失败: {error}")))?;
        files::write_file_mode(&self.backup_path(), &json, 0o600)
            .map_err(|error| PlatformError::message(format!("写入 dnsmasq 备份失败: {error}")))?;
        let script = render_restore_script(backup);
        let _ = files::write_file_mode(&self.restore_script_path(), script.as_bytes(), 0o700);
        Ok(())
    }

    fn clear_backup(&self) {
        let _ = files::remove_file_if_exists(&self.backup_path());
    }

    async fn ensure_original_backup(&self, cfg: &OpenWrtConfig) -> PlatformResult<DnsmasqBackup> {
        if let Some(existing) = self.read_backup() {
            return Ok(existing);
        }
        let executor = self.executor.as_ref();
        let raw_port = uci::get_option(executor, &format!("{DNSMASQ_SECTION}.port")).await;
        let raw_noresolv = uci::get_option(executor, &format!("{DNSMASQ_SECTION}.noresolv")).await;
        let raw_cachesize =
            uci::get_option(executor, &format!("{DNSMASQ_SECTION}.cachesize")).await;
        let raw_servers = uci::get_list(executor, &format!("{DNSMASQ_SECTION}.server")).await;
        let local_domain = detect_uci_local_domain(executor).await;

        // 防御异常残留：若当前端口已是谛听辅端口或 server 指向回环，剥离谛听自身痕迹后再存档。
        let aux_port = cfg.dnsmasq_port.to_string();
        let port = raw_port.filter(|val| val.trim() != aux_port);
        let servers: Vec<String> = raw_servers
            .into_iter()
            .filter(|srv| !is_diting_loopback_upstream(srv))
            .collect();
        let noresolv = if servers.is_empty() && raw_noresolv.as_deref() == Some("1") {
            None
        } else {
            raw_noresolv
        };

        let backup = DnsmasqBackup {
            port,
            noresolv,
            cachesize: raw_cachesize,
            servers,
            local_domain,
        };
        self.write_backup(&backup)?;
        Ok(backup)
    }

    pub async fn apply_openwrt_takeover(&self) -> PlatformResult<()> {
        let cfg = self.openwrt_config();
        let backup = self.ensure_original_backup(&cfg).await?;
        let executor = self.executor.as_ref();

        let adapter_state = if cfg.is_replace_mode() {
            apply_replace_mode(executor, &cfg, &backup).await?;
            let target_port = 53;
            let _ = self
                .firewall
                .configure_dns_redirect(cfg.force_redirect_53, target_port)
                .await;
            AdapterState {
                id: OPENWRT_MODE_REPLACE_DNSMASQ.to_string(),
                name: format!("接管 53 端口 (dnsmasq 辅端口 {})", cfg.dnsmasq_port),
                description: format!("内网域名 .{} 回流 dnsmasq", backup.local_domain),
                ipv4_dhcp: true,
                ipv6_dhcp: true,
                ..AdapterState::default()
            }
        } else {
            apply_upstream_mode(executor, &cfg, &backup).await?;
            let _ = self
                .firewall
                .configure_dns_redirect(cfg.force_redirect_53, 53)
                .await;
            AdapterState {
                id: OPENWRT_MODE_DNSMASQ_UPSTREAM.to_string(),
                name: format!("作为 dnsmasq 上游 (127.0.0.1#{})", cfg.upstream_port),
                description: "兼容依赖 dnsmasq 的代理分流插件".to_string(),
                ipv4_dhcp: true,
                ipv6_dhcp: true,
                ..AdapterState::default()
            }
        };

        let adapters = vec![adapter_state];
        let persisted = TakeoverState {
            active: true,
            version: self.version.clone(),
            pid: std::process::id() as i32,
            timestamp: FileStateStore::timestamp_now(),
            adapters: adapters.clone(),
        };
        self.state_store
            .save(&persisted)
            .map_err(|error| PlatformError::message(format!("保存接管状态失败: {error}")))?;

        let mut rt = self
            .runtime
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        rt.active = true;
        rt.adapters = adapters;
        rt.local_domain = backup.local_domain;
        Ok(())
    }

    async fn restore_from_backup_or_fallback(&self) -> PlatformResult<()> {
        let executor = self.executor.as_ref();
        if let Some(backup) = self.read_backup() {
            restore_dnsmasq_from_backup(executor, &backup).await?;
        } else {
            fallback_clean_dnsmasq(executor, &self.openwrt_config()).await?;
        }
        let _ = self.firewall.configure_dns_redirect(false, 53).await;
        self.clear_backup();
        let _ = self.state_store.clear();
        let mut rt = self
            .runtime
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        rt.active = false;
        rt.adapters.clear();
        Ok(())
    }
}

async fn detect_uci_local_domain(executor: &dyn CommandExecutor) -> String {
    if let Some(domain) = uci::get_option(executor, &format!("{DNSMASQ_SECTION}.domain")).await {
        let cleaned = domain.trim().trim_matches('.').to_string();
        if !cleaned.is_empty() {
            return cleaned;
        }
    }
    if let Some(local) = uci::get_option(executor, &format!("{DNSMASQ_SECTION}.local")).await {
        let cleaned = local.trim().trim_matches('/').trim_matches('.').to_string();
        if !cleaned.is_empty() {
            return cleaned;
        }
    }
    "lan".to_string()
}

fn is_diting_loopback_upstream(server: &str) -> bool {
    let trimmed = server.trim();
    trimmed.starts_with("127.0.0.1#")
        || trimmed.starts_with("::1#")
        || trimmed == "127.0.0.1"
        || trimmed == "::1"
}

async fn apply_replace_mode(
    executor: &dyn CommandExecutor,
    cfg: &OpenWrtConfig,
    backup: &DnsmasqBackup,
) -> PlatformResult<()> {
    let aux_port = cfg.dnsmasq_port.to_string();
    uci::set_option(executor, &format!("{DNSMASQ_SECTION}.port"), &aux_port).await?;
    restore_optional_key(
        executor,
        &format!("{DNSMASQ_SECTION}.noresolv"),
        backup.noresolv.as_deref(),
    )
    .await?;
    restore_optional_key(
        executor,
        &format!("{DNSMASQ_SECTION}.cachesize"),
        backup.cachesize.as_deref(),
    )
    .await?;
    uci::set_list(
        executor,
        &format!("{DNSMASQ_SECTION}.server"),
        &backup.servers,
    )
    .await?;
    uci::commit(executor, "dhcp").await?;
    uci::init_action(executor, "dnsmasq", "restart").await
}

async fn apply_upstream_mode(
    executor: &dyn CommandExecutor,
    cfg: &OpenWrtConfig,
    backup: &DnsmasqBackup,
) -> PlatformResult<()> {
    restore_optional_key(
        executor,
        &format!("{DNSMASQ_SECTION}.port"),
        backup.port.as_deref(),
    )
    .await?;
    uci::set_option(executor, &format!("{DNSMASQ_SECTION}.noresolv"), "1").await?;
    uci::set_option(executor, &format!("{DNSMASQ_SECTION}.cachesize"), "0").await?;
    let upstream = vec![format!("127.0.0.1#{}", cfg.upstream_port)];
    uci::set_list(executor, &format!("{DNSMASQ_SECTION}.server"), &upstream).await?;
    uci::commit(executor, "dhcp").await?;
    uci::init_action(executor, "dnsmasq", "restart").await
}

async fn restore_dnsmasq_from_backup(
    executor: &dyn CommandExecutor,
    backup: &DnsmasqBackup,
) -> PlatformResult<()> {
    restore_optional_key(
        executor,
        &format!("{DNSMASQ_SECTION}.port"),
        backup.port.as_deref(),
    )
    .await?;
    restore_optional_key(
        executor,
        &format!("{DNSMASQ_SECTION}.noresolv"),
        backup.noresolv.as_deref(),
    )
    .await?;
    restore_optional_key(
        executor,
        &format!("{DNSMASQ_SECTION}.cachesize"),
        backup.cachesize.as_deref(),
    )
    .await?;
    uci::set_list(
        executor,
        &format!("{DNSMASQ_SECTION}.server"),
        &backup.servers,
    )
    .await?;
    uci::commit(executor, "dhcp").await?;
    uci::init_action(executor, "dnsmasq", "restart").await
}

async fn fallback_clean_dnsmasq(
    executor: &dyn CommandExecutor,
    cfg: &OpenWrtConfig,
) -> PlatformResult<()> {
    let mut changed = false;
    if let Some(port) = uci::get_option(executor, &format!("{DNSMASQ_SECTION}.port")).await {
        if port.trim() == cfg.dnsmasq_port.to_string() {
            uci::delete_key(executor, &format!("{DNSMASQ_SECTION}.port")).await?;
            changed = true;
        }
    }
    let servers = uci::get_list(executor, &format!("{DNSMASQ_SECTION}.server")).await;
    let remaining: Vec<String> = servers
        .iter()
        .filter(|srv| !is_diting_loopback_upstream(srv))
        .cloned()
        .collect();
    if remaining.len() != servers.len() {
        uci::set_list(executor, &format!("{DNSMASQ_SECTION}.server"), &remaining).await?;
        if remaining.is_empty() {
            uci::delete_key(executor, &format!("{DNSMASQ_SECTION}.noresolv")).await?;
            uci::delete_key(executor, &format!("{DNSMASQ_SECTION}.cachesize")).await?;
        }
        changed = true;
    }
    if changed {
        uci::commit(executor, "dhcp").await?;
        uci::init_action(executor, "dnsmasq", "restart").await?;
    }
    Ok(())
}

async fn restore_optional_key(
    executor: &dyn CommandExecutor,
    key: &str,
    original: Option<&str>,
) -> PlatformResult<()> {
    match original {
        Some(value) if !value.is_empty() => uci::set_option(executor, key, value).await,
        _ => uci::delete_key(executor, key).await,
    }
}

fn render_restore_script(backup: &DnsmasqBackup) -> String {
    let mut lines = vec![
        "#!/bin/sh".to_string(),
        "# 谛听 (DITING) OpenWrt DNS 紧急恢复脚本".to_string(),
        "set -e".to_string(),
    ];
    match &backup.port {
        Some(port) => lines.push(format!("uci set {DNSMASQ_SECTION}.port='{port}'")),
        None => lines.push(format!("uci -q delete {DNSMASQ_SECTION}.port || true")),
    }
    match &backup.noresolv {
        Some(val) => lines.push(format!("uci set {DNSMASQ_SECTION}.noresolv='{val}'")),
        None => lines.push(format!("uci -q delete {DNSMASQ_SECTION}.noresolv || true")),
    }
    match &backup.cachesize {
        Some(val) => lines.push(format!("uci set {DNSMASQ_SECTION}.cachesize='{val}'")),
        None => lines.push(format!("uci -q delete {DNSMASQ_SECTION}.cachesize || true")),
    }
    lines.push(format!("uci -q delete {DNSMASQ_SECTION}.server || true"));
    for srv in &backup.servers {
        lines.push(format!("uci add_list {DNSMASQ_SECTION}.server='{srv}'"));
    }
    lines.push("uci commit dhcp".to_string());
    lines.push("uci -q delete firewall.diting_dns_redirect || true".to_string());
    lines.push("uci commit firewall || true".to_string());
    lines.push("/etc/init.d/dnsmasq restart".to_string());
    lines.push("/etc/init.d/firewall reload || true".to_string());
    lines.join("\n") + "\n"
}

#[async_trait]
impl DnsManager for OpenWrtDnsManager {
    async fn takeover(&self, _adapters: &[AdapterInfo]) -> PlatformResult<()> {
        self.apply_openwrt_takeover().await
    }

    async fn takeover_single(&self, _adapter: &AdapterInfo) -> PlatformResult<()> {
        self.apply_openwrt_takeover().await
    }

    async fn restore(&self) -> PlatformResult<()> {
        self.restore_from_backup_or_fallback().await
    }

    async fn restore_single(&self, _adapter_id: &str) -> PlatformResult<()> {
        self.restore_from_backup_or_fallback().await
    }

    async fn restore_adapters(&self, _adapters: &[AdapterState]) -> PlatformResult<()> {
        self.restore_from_backup_or_fallback().await
    }

    async fn reset_residual_loopback_dns(&self) -> PlatformResult<()> {
        self.restore_from_backup_or_fallback().await
    }

    fn is_takeover_active(&self) -> bool {
        self.runtime
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .active
    }

    fn taken_over_adapters(&self) -> Vec<AdapterState> {
        self.runtime
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .adapters
            .clone()
    }

    async fn flush_dns_cache(&self) -> PlatformResult<()> {
        Ok(())
    }
}

pub struct OpenWrtAdapterScanner;

impl OpenWrtAdapterScanner {
    pub fn new() -> Self {
        Self
    }
}

impl Default for OpenWrtAdapterScanner {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl AdapterScanner for OpenWrtAdapterScanner {
    async fn scan_all(&self) -> PlatformResult<Vec<AdapterInfo>> {
        let lan_ips = super::lan_addresses().unwrap_or_default();
        let primary_ip = lan_ips
            .first()
            .cloned()
            .unwrap_or_else(|| "192.168.1.1".to_string());
        Ok(vec![AdapterInfo {
            id: "br-lan".to_string(),
            name: "br-lan".to_string(),
            description: "OpenWrt LAN 桥接网络与 dnsmasq".to_string(),
            index: 1,
            status: "Up".to_string(),
            gateway: primary_ip,
            ipv4_dhcp: true,
            ipv6_dhcp: true,
            is_physical: true,
            ..AdapterInfo::default()
        }])
    }

    async fn active_physical_adapters(&self) -> PlatformResult<Vec<AdapterInfo>> {
        self.scan_all().await
    }
}

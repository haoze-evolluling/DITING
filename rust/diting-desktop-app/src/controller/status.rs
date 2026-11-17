//! Status, takeover, port diagnosis and background-service reporting.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use diting_desktop_api::config::{
    AccessControlConfig, DNS64Config, ECSConfig, HostsConfig, RateLimitConfig, RebindConfig,
    RewriteConfig, SafeBrowsingConfig, SafeSearchConfig, ZoneConfig,
};
use diting_desktop_api::platform_types::PortCheckResult;
use diting_desktop_api::platform_types::{AdapterInfo, AdapterState, CoreServiceStatus};
use diting_desktop_platform::error::PlatformResult;
use diting_desktop_platform::traits::{DnsManager, Restorer};

use crate::controller::cache::CacheStats;
use crate::controller::filter::FilterStats;
use crate::controller::{effective_listen_addresses, ControllerError};
use crate::runtime::PlatformHandles;
use crate::AppRuntime;

/// `ipc.UpstreamInfo`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpstreamInfo {
    pub id: String,
    pub protocol: String,
    pub server: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub url: String,
    pub weight: i32,
    pub active: bool,
    pub success_count: u64,
    pub failure_count: u64,
    pub avg_latency_ms: f64,
    #[serde(skip_serializing_if = "is_false")]
    pub pin_set: bool,
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// `ipc.DNSStatus`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DnsStatus {
    pub running: bool,
    pub listen_addresses: Vec<String>,
    #[serde(rename = "allowLAN")]
    pub allow_lan: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub lan_addresses: Vec<String>,
    pub mode: String,
    pub upstreams: Vec<UpstreamInfo>,
    pub bootstrap: diting_desktop_api::config::BootstrapConfig,
    #[serde(skip_serializing_if = "std::collections::HashMap::is_empty")]
    pub conditional_routes: std::collections::HashMap<String, String>,
    #[serde(rename = "enableEDE")]
    pub enable_ede: bool,
    pub block_unqualified: bool,
    #[serde(rename = "blockPrivatePTR")]
    pub block_private_ptr: bool,
    #[serde(rename = "blockIPv6")]
    pub block_ipv6: bool,
    #[serde(rename = "blockECH")]
    pub block_ech: bool,
    pub edns_padding: i32,
    #[serde(rename = "blockANY")]
    pub block_any: bool,
    #[serde(rename = "blockANYMode")]
    pub block_any_mode: String,
}

/// `ipc.TakeoverStatus`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TakeoverStatus {
    pub active: bool,
    pub adapters: Vec<AdapterState>,
}

/// `ipc.MetricsStatus`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricsStatus {
    pub total_queries: u64,
    pub success_queries: u64,
    pub failed_queries: u64,
    pub avg_latency_ms: f64,
    pub qps: f64,
}

/// `ipc.StatusResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StatusResponse {
    pub version: String,
    #[serde(rename = "pid")]
    pub pid: u32,
    pub uptime_seconds: i64,
    pub dns: DnsStatus,
    pub takeover: TakeoverStatus,
    pub metrics: MetricsStatus,
    pub cache: CacheStats,
    pub filter: FilterStats,
    pub hosts: HostsConfig,
    pub rebind: RebindConfig,
    pub access: AccessControlConfig,
    pub rate_limit: RateLimitConfig,
    pub dns64: DNS64Config,
    pub rewrite: RewriteConfig,
    pub zone: ZoneConfig,
    pub safe_search: SafeSearchConfig,
    pub safe_browsing: SafeBrowsingConfig,
    pub ecs: ECSConfig,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub clients: Vec<ClientSummary>,
}

/// Client projection used by `status` (Go's `core.ClientInfo`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientSummary {
    pub ip: String,
    pub name: String,
    pub query_count: u64,
    pub last_seen: i64,
}

/// `ipc.EmergencyRestoreResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EmergencyRestoreResponse {
    pub healed: bool,
    pub message: String,
}

/// `ipc.AdapterTakeoverRequest`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdapterTakeoverRequest {
    #[serde(default)]
    pub adapter_id: String,
    #[serde(default)]
    pub enable: bool,
}

struct ManagerRestorer(std::sync::Arc<dyn DnsManager>);

#[async_trait]
impl Restorer for ManagerRestorer {
    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        self.0.restore_adapters(adapters).await
    }
}

fn require_platform(
    runtime: &AppRuntime,
) -> Result<std::sync::Arc<PlatformHandles>, ControllerError> {
    runtime
        .platform()
        .ok_or_else(|| ControllerError::new("平台能力未初始化"))
}

pub(crate) fn client_summaries(runtime: &AppRuntime) -> Vec<ClientSummary> {
    runtime
        .clients
        .info()
        .into_iter()
        .map(|client| ClientSummary {
            ip: client.ip.to_string(),
            name: client.name,
            query_count: client.query_count,
            last_seen: if client.last_seen_ms > 0 {
                client.last_seen_ms / 1000
            } else {
                0
            },
        })
        .collect()
}

impl AppRuntime {
    /// `GetStatus`.
    pub fn status(&self) -> StatusResponse {
        let config = self.config();
        let lan_addresses = self.lan_addresses();
        let effective_udp = effective_listen_addresses(&config.dns).0;

        let upstreams = config
            .upstream
            .providers
            .iter()
            .map(|provider| UpstreamInfo {
                id: provider.id.clone(),
                protocol: provider.protocol.to_ascii_uppercase(),
                server: provider.server.clone(),
                url: provider.url.clone(),
                weight: if provider.weight > 0 {
                    provider.weight
                } else {
                    1
                },
                active: true,
                success_count: 0,
                failure_count: 0,
                avg_latency_ms: 0.0,
                pin_set: !provider.pin.trim().is_empty(),
            })
            .collect();

        let (takeover_active, adapters) = self
            .platform()
            .and_then(|platform| platform.dns_manager.clone())
            .map(|manager| (manager.is_takeover_active(), manager.taken_over_adapters()))
            .unwrap_or((false, Vec::new()));

        let snapshot = self.metrics.snapshot();

        StatusResponse {
            version: diting_desktop_api::version::VERSION.to_string(),
            pid: std::process::id(),
            uptime_seconds: self.metrics.uptime_seconds(),
            dns: DnsStatus {
                running: self.is_dns_running(),
                listen_addresses: effective_udp,
                allow_lan: config.dns.allow_lan,
                lan_addresses,
                mode: config.upstream.mode.clone(),
                upstreams,
                bootstrap: config.upstream.bootstrap.clone(),
                conditional_routes: config.upstream.conditional_routes.clone(),
                enable_ede: config.dns.enable_ede,
                block_unqualified: config.dns.block_unqualified,
                block_private_ptr: config.dns.block_private_ptr,
                block_ipv6: config.dns.block_ipv6,
                block_ech: config.dns.block_ech,
                edns_padding: config.dns.edns_padding,
                block_any: config.dns.block_any,
                block_any_mode: config.dns.block_any_mode.clone(),
            },
            takeover: TakeoverStatus {
                active: takeover_active,
                adapters,
            },
            metrics: MetricsStatus {
                total_queries: snapshot.total_queries,
                success_queries: snapshot.success_queries,
                failed_queries: snapshot.failed_queries,
                avg_latency_ms: snapshot.avg_latency_ms,
                qps: snapshot.qps,
            },
            cache: self.cache_stats(),
            filter: self.filter_stats(),
            hosts: config.hosts,
            rebind: config.rebind,
            access: config.access,
            rate_limit: config.rate_limit,
            dns64: config.dns64,
            rewrite: config.rewrite,
            zone: config.zone,
            safe_search: config.safe_search,
            safe_browsing: config.safe_browsing,
            ecs: config.ecs,
            clients: client_summaries(self),
        }
    }

    pub fn metrics_status(&self) -> MetricsStatus {
        let snapshot = self.metrics.snapshot();
        MetricsStatus {
            total_queries: snapshot.total_queries,
            success_queries: snapshot.success_queries,
            failed_queries: snapshot.failed_queries,
            avg_latency_ms: snapshot.avg_latency_ms,
            qps: snapshot.qps,
        }
    }

    /// `GetAdapters`.
    pub async fn adapters(&self) -> Result<Vec<AdapterInfo>, ControllerError> {
        let platform = require_platform(self)?;
        let scanner = platform
            .adapters
            .clone()
            .ok_or_else(|| ControllerError::new("网卡扫描器未初始化"))?;
        scanner
            .scan_all()
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    /// `EnableTakeover`.
    pub async fn enable_takeover(&self) -> Result<(), ControllerError> {
        let platform = require_platform(self)?;
        if !self.is_dns_running() {
            self.start_dns_checked().await?;
        }
        let scanner = platform
            .adapters
            .clone()
            .ok_or_else(|| ControllerError::new("网卡扫描器未初始化"))?;
        let manager = platform
            .dns_manager
            .clone()
            .ok_or_else(|| ControllerError::new("DNS 接管管理器未初始化"))?;
        let adapters = scanner
            .active_physical_adapters()
            .await
            .map_err(|error| ControllerError::new(format!("枚举活动物理网卡失败: {error}")))?;
        if adapters.is_empty() {
            return Err(ControllerError::new(
                "未检测到有效活动的物理网卡（以太网或 Wi-Fi）",
            ));
        }
        manager
            .takeover(&adapters)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    /// `DisableTakeover`.
    pub async fn disable_takeover(&self) -> Result<(), ControllerError> {
        let platform = require_platform(self)?;
        let manager = platform
            .dns_manager
            .clone()
            .ok_or_else(|| ControllerError::new("DNS 接管管理器未初始化"))?;
        manager
            .restore()
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    /// `SetAdapterTakeover`.
    pub async fn set_adapter_takeover(
        &self,
        request: AdapterTakeoverRequest,
    ) -> Result<(), ControllerError> {
        let platform = require_platform(self)?;
        let manager = platform
            .dns_manager
            .clone()
            .ok_or_else(|| ControllerError::new("DNS 接管管理器未初始化"))?;
        if !request.enable {
            return manager
                .restore_single(&request.adapter_id)
                .await
                .map_err(|error| ControllerError::new(error.to_string()));
        }
        let scanner = platform
            .adapters
            .clone()
            .ok_or_else(|| ControllerError::new("网卡扫描器未初始化"))?;
        let adapters = scanner
            .scan_all()
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        let target = adapters
            .into_iter()
            .find(|adapter| adapter.id == request.adapter_id || adapter.name == request.adapter_id)
            .ok_or_else(|| ControllerError::new(format!("找不到网卡: {}", request.adapter_id)))?;
        manager
            .takeover_single(&target)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    /// `EmergencyRestore`.
    pub async fn emergency_restore(&self) -> Result<EmergencyRestoreResponse, ControllerError> {
        let platform = require_platform(self)?;
        let store = platform
            .state_store
            .clone()
            .ok_or_else(|| ControllerError::new("系统状态存储未就绪"))?;
        let manager = platform
            .dns_manager
            .clone()
            .ok_or_else(|| ControllerError::new("DNS 管理器未就绪"))?;
        let restorer = ManagerRestorer(std::sync::Arc::clone(&manager));
        let healed = store
            .check_and_self_heal(Some(&restorer))
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        manager
            .reset_residual_loopback_dns()
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        manager
            .flush_dns_cache()
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        Ok(if healed {
            EmergencyRestoreResponse {
                healed: true,
                message: "已成功恢复网络 DNS 设置！".to_string(),
            }
        } else {
            EmergencyRestoreResponse {
                healed: false,
                message: "网络 DNS 状态正常，无需修复。".to_string(),
            }
        })
    }

    /// `CheckPortConflicts`.
    pub async fn port_check(&self) -> Result<PortCheckResult, ControllerError> {
        let platform = require_platform(self)?;
        let checker = platform
            .port_checker
            .clone()
            .ok_or_else(|| ControllerError::new("端口检测器未初始化"))?;
        let config = self.config();
        let (udp, tcp) = effective_listen_addresses(&config.dns);
        checker
            .check_port53_for_addresses(&udp, &tcp)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    /// `AutofixPortConflicts`.
    pub async fn port_autofix(&self, start_dns: bool) -> Result<PortCheckResult, ControllerError> {
        let platform = require_platform(self)?;
        let checker = platform
            .port_checker
            .clone()
            .ok_or_else(|| ControllerError::new("端口检测器未初始化"))?;
        let config = self.config();
        let (udp, tcp) = effective_listen_addresses(&config.dns);
        let result = checker
            .autofix_port53_for_addresses(&udp, &tcp)
            .await
            .map_err(|error| ControllerError::new(format!("自动修复端口冲突失败: {error}")))?;
        if start_dns && result.available && !self.is_dns_running() {
            self.start_dns_checked().await?;
        }
        Ok(result)
    }

    /// `GetCoreServiceStatus`, including the foreground-mode description.
    pub async fn core_service_status(&self) -> Result<CoreServiceStatus, ControllerError> {
        let platform = require_platform(self)?;
        let manager = platform
            .service_manager
            .clone()
            .ok_or_else(|| ControllerError::new("后台核心服务管理器未初始化"))?;
        let mut status = match manager.status().await {
            Ok(status) => status,
            Err(error) => {
                return Err(ControllerError::new(error.to_string()));
            }
        };
        if !status.installed {
            if status.executable_path.is_empty() {
                if let Ok(exe) = std::env::current_exe() {
                    status.executable_path = exe.to_string_lossy().into_owned();
                    status.can_install = true;
                }
            }
            status.running = true;
            status.state = "foreground".to_string();
            status.state_text = "前台运行中".to_string();
            status.message = if self.is_dns_running() {
                "核心服务未注册为系统服务，当前以前台模式运行并正常提供 DNS 解析。".to_string()
            } else {
                "核心服务未注册为系统服务，当前以前台模式运行，DNS 监听器尚未启动。".to_string()
            };
        }
        status.is_elevated = platform.is_elevated;
        Ok(status)
    }

    pub fn platform_name(&self) -> String {
        self.platform()
            .map(|platform| platform.platform_name.clone())
            .unwrap_or_else(|| std::env::consts::OS.to_string())
    }

    pub fn is_elevated(&self) -> bool {
        self.platform()
            .map(|platform| platform.is_elevated)
            .unwrap_or(false)
    }
}

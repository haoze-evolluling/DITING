//! Platform capability traits.
//!
//! These mirror `desktop/service/internal/platform/interfaces.go`. The service composes one
//! implementation per OS and the IPC layer talks only to these traits, which keeps the handlers
//! testable with in-memory fakes.

use std::path::Path;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{
    AdapterInfo, AdapterState, AutoStartStatus, CoreServiceStatus, PortCheckResult, TakeoverState,
};

use crate::error::PlatformResult;

#[async_trait]
pub trait AdapterScanner: Send + Sync {
    async fn scan_all(&self) -> PlatformResult<Vec<AdapterInfo>>;
    async fn active_physical_adapters(&self) -> PlatformResult<Vec<AdapterInfo>>;
}

/// DNS takeover contract. Implementations must roll back on failure and clean the state file, and
/// must restore the snapshot atomically on `restore*`.
#[async_trait]
pub trait DnsManager: Send + Sync {
    async fn takeover(&self, adapters: &[AdapterInfo]) -> PlatformResult<()>;
    async fn takeover_single(&self, adapter: &AdapterInfo) -> PlatformResult<()>;
    async fn restore(&self) -> PlatformResult<()>;
    async fn restore_single(&self, adapter_id: &str) -> PlatformResult<()>;
    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()>;
    /// Resets any DNS setting that still points at the local loopback resolver.
    async fn reset_residual_loopback_dns(&self) -> PlatformResult<()>;
    fn is_takeover_active(&self) -> bool;
    fn taken_over_adapters(&self) -> Vec<AdapterState>;
    async fn flush_dns_cache(&self) -> PlatformResult<()>;
}

/// The narrow slice of [`DnsManager`] crash recovery needs; tests can implement only this.
#[async_trait]
pub trait Restorer: Send + Sync {
    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()>;
}

#[async_trait]
pub trait StateStore: Send + Sync {
    fn save(&self, state: &TakeoverState) -> PlatformResult<()>;
    fn load(&self) -> PlatformResult<Option<TakeoverState>>;
    fn clear(&self) -> PlatformResult<()>;
    fn file_path(&self) -> &Path;

    /// Restores a leftover active takeover and clears the state file. Returns whether healing ran.
    async fn check_and_self_heal(&self, restorer: Option<&dyn Restorer>) -> PlatformResult<bool> {
        let Some(state) = self.load()? else {
            return Ok(false);
        };
        if !state.active || state.adapters.is_empty() {
            return Ok(false);
        }
        if let Some(restorer) = restorer {
            restorer.restore_adapters(&state.adapters).await?;
        }
        self.clear()?;
        Ok(true)
    }
}

#[async_trait]
pub trait PortChecker: Send + Sync {
    async fn check_port53(&self) -> PlatformResult<PortCheckResult>;
    async fn check_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult>;
    async fn autofix_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult>;
}

/// Windows elevates through UAC; Linux has no equivalent, so it runs as the current user.
#[async_trait]
pub trait PrivilegedExecutor: Send + Sync {
    async fn run_elevated(&self, exe: &str, args: &[String]) -> PlatformResult<()>;
    fn is_elevated(&self) -> bool;
}

#[async_trait]
pub trait ServiceManager: Send + Sync {
    async fn status(&self) -> PlatformResult<CoreServiceStatus>;
    async fn start(&self) -> PlatformResult<()>;
    async fn stop(&self) -> PlatformResult<()>;
    async fn restart(&self) -> PlatformResult<()>;
    async fn install(&self, exe_path: &str) -> PlatformResult<()>;
    async fn install_and_start(&self, exe_path: &str) -> PlatformResult<()>;
    async fn uninstall(&self) -> PlatformResult<()>;
    fn locate_executable(&self) -> PlatformResult<String>;
}

pub trait AutoStartManager: Send + Sync {
    fn is_enabled(&self) -> bool;
    fn set_enabled(&self, enable: bool) -> PlatformResult<AutoStartStatus>;
}

#[async_trait]
pub trait FirewallManager: Send + Sync {
    async fn check_port53(&self) -> PlatformResult<bool>;
    async fn configure_port53(&self, enable: bool) -> PlatformResult<()>;
    async fn check_web(&self) -> PlatformResult<bool>;
    async fn configure_web(&self, port: i32, enable: bool) -> PlatformResult<()>;
}

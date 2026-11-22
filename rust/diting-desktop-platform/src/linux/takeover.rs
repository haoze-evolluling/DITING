use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use diting_desktop_api::platform_types::{AdapterInfo, AdapterState, TakeoverState};
use tokio::sync::OnceCell;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::netutil::clean_adapter_state;
use crate::state::FileStateStore;
use crate::traits::{AdapterScanner, DnsManager, StateStore};

use super::adapter::LinuxAdapterScanner;
use super::backend::{self, DnsBackend};
use super::restore_script::generate_restore_script;

#[derive(Default)]
struct ManagerState {
    active: bool,
    adapters: Vec<AdapterState>,
}

pub struct LinuxDnsManager {
    executor: Arc<dyn CommandExecutor>,
    state_store: Arc<dyn StateStore>,
    backend: OnceCell<DnsBackend>,
    state: Mutex<ManagerState>,
    version: String,
}

impl LinuxDnsManager {
    pub fn new(
        executor: Arc<dyn CommandExecutor>,
        store: Arc<dyn StateStore>,
        version: impl Into<String>,
    ) -> Self {
        let version = version.into();
        Self {
            executor,
            state_store: store,
            backend: OnceCell::new(),
            state: Mutex::new(ManagerState::default()),
            version: if version.is_empty() {
                "dev".to_string()
            } else {
                version
            },
        }
    }

    async fn backend(&self) -> DnsBackend {
        *self
            .backend
            .get_or_init(|| async { backend::detect_backend(self.executor.as_ref()).await })
            .await
    }

    fn lock_state(&self) -> std::sync::MutexGuard<'_, ManagerState> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn persist(&self, active: bool, adapters: Vec<AdapterState>) -> TakeoverState {
        TakeoverState {
            active,
            version: self.version.clone(),
            pid: std::process::id() as i32,
            timestamp: FileStateStore::timestamp_now(),
            adapters,
        }
    }

    fn restore_script_path(&self) -> std::path::PathBuf {
        match self.state_store.file_path().parent() {
            Some(parent) => parent.join("restore-dns.sh"),
            None => std::path::PathBuf::from("restore-dns.sh"),
        }
    }

    async fn restore_snapshot(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        let cleaned: Vec<AdapterState> = adapters.iter().map(clean_adapter_state).collect();
        let backend = self.backend().await;
        let result = backend::restore(self.executor.as_ref(), backend, &cleaned).await;
        let _ = self.flush_dns_cache().await;
        result
    }
}

#[async_trait]
impl DnsManager for LinuxDnsManager {
    async fn takeover(&self, adapters: &[AdapterInfo]) -> PlatformResult<()> {
        if adapters.is_empty() {
            return Err(PlatformError::message("无有效活动物理网卡可供接管"));
        }

        let states = adapter_infos_to_states(adapters);
        let persisted = self.persist(true, states.clone());
        self.state_store
            .save(&persisted)
            .map_err(|error| PlatformError::message(format!("接管前保存状态失败: {error}")))?;

        let backend = self.backend().await;
        let _ = generate_restore_script(backend, &states, &self.restore_script_path());

        if let Err(error) = backend::apply(self.executor.as_ref(), backend, adapters).await {
            match backend::restore(self.executor.as_ref(), backend, &states).await {
                Ok(()) => {
                    let _ = self.state_store.clear();
                    return Err(PlatformError::message(format!(
                        "接管网卡 DNS 失败: {error}"
                    )));
                }
                Err(restore_error) => {
                    return Err(PlatformError::message(format!(
                        "接管网卡 DNS 失败: {error}（回滚亦失败: {restore_error}，已保留状态文件）"
                    )));
                }
            }
        }

        let _ = self.flush_dns_cache().await;
        {
            let mut state = self.lock_state();
            state.active = true;
            state.adapters = states;
        }
        Ok(())
    }

    async fn takeover_single(&self, adapter: &AdapterInfo) -> PlatformResult<()> {
        let snapshot = adapter_info_to_state(adapter);

        let (old_adapters, old_active, current_adapters) = {
            let mut state = self.lock_state();
            let old_adapters = state.adapters.clone();
            let old_active = state.active;
            match state
                .adapters
                .iter()
                .position(|current| current.id == adapter.id || current.name == adapter.name)
            {
                Some(index) => state.adapters[index] = snapshot.clone(),
                None => state.adapters.push(snapshot.clone()),
            }
            (old_adapters, old_active, state.adapters.clone())
        };

        let persisted = self.persist(true, current_adapters.clone());
        if let Err(error) = self.state_store.save(&persisted) {
            self.lock_state().adapters = old_adapters;
            return Err(PlatformError::message(format!(
                "接管前保存状态失败: {error}"
            )));
        }

        let backend = self.backend().await;
        let _ = generate_restore_script(backend, &current_adapters, &self.restore_script_path());

        if let Err(error) = backend::apply(
            self.executor.as_ref(),
            backend,
            std::slice::from_ref(adapter),
        )
        .await
        {
            let restore_error = backend::restore(
                self.executor.as_ref(),
                backend,
                std::slice::from_ref(&snapshot),
            )
            .await;

            {
                let mut state = self.lock_state();
                state.adapters = old_adapters.clone();
                state.active = old_active;
            }
            if old_adapters.is_empty() {
                let _ = self.state_store.clear();
            } else {
                let rollback = self.persist(old_active, old_adapters);
                let _ = self.state_store.save(&rollback);
            }

            return match restore_error {
                Ok(()) => Err(error),
                Err(restore_error) => Err(PlatformError::message(format!(
                    "{error}（回滚亦失败: {restore_error}）"
                ))),
            };
        }

        let _ = self.flush_dns_cache().await;
        self.lock_state().active = true;
        Ok(())
    }

    async fn restore(&self) -> PlatformResult<()> {
        let current = {
            let state = self.lock_state();
            state.adapters.clone()
        };
        let targets = if !current.is_empty() {
            Some(current)
        } else {
            match self.state_store.load() {
                Ok(Some(state)) if !state.adapters.is_empty() => Some(state.adapters),
                _ => None,
            }
        };

        let result = match targets {
            Some(adapters) => self.restore_snapshot(&adapters).await,
            None => Ok(()),
        };

        if result.is_ok() {
            {
                let mut state = self.lock_state();
                state.active = false;
                state.adapters.clear();
            }
            let _ = self.state_store.clear();
        }

        let _ = self.reset_residual_loopback_dns().await;
        result
    }

    async fn restore_single(&self, adapter_id: &str) -> PlatformResult<()> {
        let (targets, remaining) = {
            let state = self.lock_state();
            let mut targets = Vec::new();
            let mut remaining = Vec::new();
            for adapter in &state.adapters {
                if adapter.id == adapter_id || adapter.name == adapter_id {
                    targets.push(adapter.clone());
                } else {
                    remaining.push(adapter.clone());
                }
            }
            (targets, remaining)
        };

        if targets.is_empty() {
            return Ok(());
        }

        self.restore_snapshot(&targets).await?;

        {
            let mut state = self.lock_state();
            state.adapters = remaining.clone();
            if remaining.is_empty() {
                state.active = false;
            }
        }
        if remaining.is_empty() {
            let _ = self.state_store.clear();
        } else {
            let persisted = self.persist(true, remaining);
            let _ = self.state_store.save(&persisted);
        }
        Ok(())
    }

    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        self.restore_snapshot(adapters).await
    }

    async fn reset_residual_loopback_dns(&self) -> PlatformResult<()> {
        let scanner = LinuxAdapterScanner::new(self.executor.clone());
        let adapters = scanner.scan_all().await?;

        let residual: Vec<AdapterState> = adapters
            .iter()
            .filter(|adapter| adapter.has_residual_loopback)
            .map(adapter_info_to_state)
            .collect();
        if residual.is_empty() {
            return Ok(());
        }

        let backend = self.backend().await;
        let result = backend::restore(self.executor.as_ref(), backend, &residual).await;
        let _ = self.flush_dns_cache().await;
        result
    }

    fn is_takeover_active(&self) -> bool {
        self.lock_state().active
    }

    fn taken_over_adapters(&self) -> Vec<AdapterState> {
        self.lock_state().adapters.clone()
    }

    async fn flush_dns_cache(&self) -> PlatformResult<()> {
        let backend = self.backend().await;
        backend::flush(self.executor.as_ref(), backend).await
    }
}

fn adapter_info_to_state(adapter: &AdapterInfo) -> AdapterState {
    clean_adapter_state(&AdapterState {
        id: adapter.id.clone(),
        name: adapter.name.clone(),
        index: adapter.index,
        description: adapter.description.clone(),
        ipv4_dhcp: adapter.ipv4_dhcp,
        ipv6_dhcp: adapter.ipv6_dhcp,
        ipv4_dns: adapter.ipv4_dns.clone(),
        ipv6_dns: adapter.ipv6_dns.clone(),
    })
}

fn adapter_infos_to_states(adapters: &[AdapterInfo]) -> Vec<AdapterState> {
    adapters.iter().map(adapter_info_to_state).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adapter_snapshots_drop_loopback_and_default_to_dhcp() {
        let adapter = AdapterInfo {
            id: "eth0".into(),
            name: "eth0".into(),
            ipv4_dns: vec!["127.0.0.1".into()],
            ipv6_dns: vec!["2001:db8::1".into()],
            ipv4_dhcp: false,
            ipv6_dhcp: false,
            ..AdapterInfo::default()
        };
        let snapshot = adapter_info_to_state(&adapter);
        assert!(snapshot.ipv4_dns.is_empty());
        assert!(snapshot.ipv4_dhcp);
        assert_eq!(snapshot.ipv6_dns, vec!["2001:db8::1".to_string()]);
        assert!(!snapshot.ipv6_dhcp);
    }
}

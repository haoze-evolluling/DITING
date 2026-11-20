use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use diting_desktop_api::platform_types::{AdapterInfo, AdapterState, TakeoverState};
use tokio::sync::Mutex as AsyncMutex;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::state::FileStateStore;
use crate::traits::{DnsManager, Restorer, StateStore};

use super::adapter_native::clean_state_for_windows;
use super::dns_native::{
    flush_dns_cache, force_reset_loopback_adapters_to_dhcp, reset_residual_loopback_dns_native,
    set_adapter_dns_dual_stack_native,
};
use super::restore_script::generate_restore_script;

#[derive(Default)]
struct DnsInner {
    active: bool,
    adapters: Vec<AdapterState>,
}

pub struct WindowsDnsManager {
    executor: Arc<dyn CommandExecutor>,
    store: Arc<dyn StateStore>,
    version: String,
    inner: Mutex<DnsInner>,
    op_lock: AsyncMutex<()>,
}

impl WindowsDnsManager {
    pub fn new(
        executor: Arc<dyn CommandExecutor>,
        store: Arc<dyn StateStore>,
        version: impl Into<String>,
    ) -> Self {
        let mut version = version.into();
        if version.is_empty() {
            version = "dev".to_string();
        }
        Self {
            executor,
            store,
            version,
            inner: Mutex::new(DnsInner::default()),
            op_lock: AsyncMutex::new(()),
        }
    }

    fn snapshot(&self) -> (bool, Vec<AdapterState>) {
        let inner = self
            .inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        (inner.active, inner.adapters.clone())
    }

    fn set_snapshot(&self, active: bool, adapters: Vec<AdapterState>) {
        let mut inner = self
            .inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        inner.active = active;
        inner.adapters = adapters;
    }

    fn persist(&self, active: bool, adapters: &[AdapterState]) -> PlatformResult<()> {
        self.store.save(&TakeoverState {
            active,
            version: self.version.clone(),
            pid: std::process::id() as i32,
            timestamp: FileStateStore::timestamp_now(),
            adapters: adapters.to_vec(),
        })
    }

    fn script_path(&self) -> PathBuf {
        let state_path = self.store.file_path();
        let directory = state_path
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        directory.join("restore-dns.bat")
    }

    fn write_restore_script(&self, adapters: &[AdapterState]) {
        let path = self.script_path();
        if let Err(error) = generate_restore_script(adapters, &path) {
            eprintln!(
                "[Takeover] 生成离线应急恢复脚本失败 ({}): {error}",
                path.display()
            );
        }
    }

    async fn apply_takeover_on_adapter(&self, adapter: &AdapterState) -> PlatformResult<()> {
        set_adapter_dns_dual_stack_native(
            self.executor.as_ref(),
            &adapter.id,
            &adapter.name,
            &["127.0.0.1".to_string()],
            &["::1".to_string()],
        )
        .await
    }

    async fn restore_single_adapter(&self, adapter: &AdapterState) -> PlatformResult<()> {
        let adapter = clean_state_for_windows(adapter);
        let v4_is_dhcp = adapter.ipv4_dhcp || adapter.ipv4_dns.is_empty();
        let v6_is_dhcp = adapter.ipv6_dhcp || adapter.ipv6_dns.is_empty();
        let v4_servers: &[String] = if v4_is_dhcp { &[] } else { &adapter.ipv4_dns };
        let v6_servers: &[String] = if v6_is_dhcp { &[] } else { &adapter.ipv6_dns };

        set_adapter_dns_dual_stack_native(
            self.executor.as_ref(),
            &adapter.id,
            &adapter.name,
            v4_servers,
            v6_servers,
        )
        .await
    }

    async fn restore_adapters_impl(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        let mut last_error = None;
        let mut failed = Vec::new();
        for adapter in adapters {
            if let Err(error) = self.restore_single_adapter(adapter).await {
                last_error = Some(error);
                failed.push(adapter.clone());
            }
        }

        if !failed.is_empty() {
            if let Err(error) =
                force_reset_loopback_adapters_to_dhcp(self.executor.as_ref(), &failed).await
            {
                eprintln!("[接管] 还原失败后的回环 DNS 兜底清理未完成: {error}");
            }
        }

        let _ = flush_dns_cache(self.executor.as_ref()).await;
        match last_error {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }

    async fn reset_residual_impl(&self) -> PlatformResult<()> {
        let result = reset_residual_loopback_dns_native(self.executor.as_ref()).await;
        let _ = flush_dns_cache(self.executor.as_ref()).await;
        result
    }
}

fn adapter_state_from_info(adapter: &AdapterInfo) -> AdapterState {
    clean_state_for_windows(&AdapterState {
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

fn merge_adapter_state(base: &[AdapterState], state: AdapterState) -> Vec<AdapterState> {
    let mut merged = base.to_vec();
    for entry in &mut merged {
        if !state.id.is_empty() && entry.id == state.id {
            *entry = state;
            return merged;
        }
    }
    merged.push(state);
    merged
}

#[async_trait]
impl DnsManager for WindowsDnsManager {
    async fn takeover(&self, adapters: &[AdapterInfo]) -> PlatformResult<()> {
        let _guard = self.op_lock.lock().await;
        if adapters.is_empty() {
            return Err(PlatformError::message("无有效活动物理网卡可供接管"));
        }

        let states: Vec<AdapterState> = adapters.iter().map(adapter_state_from_info).collect();
        self.persist(true, &states)
            .map_err(|error| PlatformError::message(format!("接管前保存状态失败: {error}")))?;
        self.write_restore_script(&states);

        for state in &states {
            if let Err(error) = self.apply_takeover_on_adapter(state).await {
                return match self.restore_adapters_impl(&states).await {
                    Ok(()) => {
                        let _ = self.store.clear();
                        Err(PlatformError::message(format!(
                            "接管网卡 [{}] 失败: {error}",
                            state.name
                        )))
                    }
                    Err(rollback) => Err(PlatformError::message(format!(
                        "接管网卡 [{}] 失败: {error}（回滚亦失败，已保留状态文件供自愈: {rollback}）",
                        state.name
                    ))),
                };
            }
        }

        let _ = flush_dns_cache(self.executor.as_ref()).await;
        self.set_snapshot(true, states);
        Ok(())
    }

    async fn takeover_single(&self, adapter: &AdapterInfo) -> PlatformResult<()> {
        let _guard = self.op_lock.lock().await;
        let state = adapter_state_from_info(adapter);
        let (old_active, old_adapters) = self.snapshot();

        let mut adapters = old_adapters.clone();
        let mut found = false;
        for entry in &mut adapters {
            if !state.id.is_empty() && entry.id == state.id {
                *entry = state.clone();
                found = true;
                break;
            }
        }
        if !found {
            adapters.push(state.clone());
        }

        if let Err(error) = self.persist(true, &adapters) {
            self.set_snapshot(old_active, old_adapters);
            return Err(PlatformError::message(format!(
                "接管前保存状态失败: {error}"
            )));
        }
        self.write_restore_script(&adapters);

        if let Err(error) = self.apply_takeover_on_adapter(&state).await {
            return match self.restore_single_adapter(&state).await {
                Ok(()) => {
                    self.set_snapshot(old_active, old_adapters.clone());
                    if old_adapters.is_empty() {
                        let _ = self.store.clear();
                    } else {
                        let _ = self.persist(old_active, &old_adapters);
                    }
                    Err(error)
                }
                Err(restore_error) => {
                    let heal_states = merge_adapter_state(&old_adapters, state);
                    let save_error = self.persist(true, &heal_states).err();
                    self.set_snapshot(old_active, old_adapters);
                    match save_error {
                        Some(save_error) => Err(PlatformError::message(format!(
                            "{error}（接管回滚失败且状态保存失败: {save_error}）"
                        ))),
                        None => Err(PlatformError::message(format!(
                            "{error}（接管回滚亦失败，已保留状态文件供自愈: {restore_error}）"
                        ))),
                    }
                }
            };
        }

        let _ = flush_dns_cache(self.executor.as_ref()).await;
        self.set_snapshot(true, adapters);
        Ok(())
    }

    async fn restore(&self) -> PlatformResult<()> {
        let _guard = self.op_lock.lock().await;
        let (_, mut states) = self.snapshot();
        if states.is_empty() {
            if let Ok(Some(persisted)) = self.store.load() {
                if !persisted.adapters.is_empty() {
                    states = persisted.adapters;
                }
            }
        }

        let result = if states.is_empty() {
            Ok(())
        } else {
            self.restore_adapters_impl(&states).await
        };

        if let Err(error) = result {
            let (_, current) = self.snapshot();
            self.set_snapshot(
                true,
                if current.is_empty() {
                    states.clone()
                } else {
                    current
                },
            );
            let _ = self.persist(true, &states);
            let _ = flush_dns_cache(self.executor.as_ref()).await;
            return Err(error);
        }

        self.set_snapshot(false, Vec::new());
        let _ = self.store.clear();
        let _ = self.reset_residual_impl().await;
        Ok(())
    }

    async fn restore_single(&self, adapter_id: &str) -> PlatformResult<()> {
        let _guard = self.op_lock.lock().await;
        let (_, current) = self.snapshot();

        let mut targets: Vec<AdapterState> = current
            .iter()
            .filter(|adapter| adapter.id == adapter_id)
            .cloned()
            .collect();
        if targets.is_empty() {
            targets = current
                .iter()
                .filter(|adapter| adapter.name == adapter_id)
                .cloned()
                .collect();
        }
        if targets.is_empty() {
            return Ok(());
        }

        let mut remaining: Vec<AdapterState> = current
            .iter()
            .filter(|adapter| !targets.iter().any(|target| target.id == adapter.id))
            .cloned()
            .collect();

        let mut restore_error = None;
        for target in &targets {
            if let Err(error) = self.restore_single_adapter(target).await {
                remaining.push(target.clone());
                restore_error = Some(error);
            }
        }

        if let Some(error) = restore_error {
            self.set_snapshot(!remaining.is_empty(), remaining.clone());
            if remaining.is_empty() {
                let _ = self.store.clear();
            } else {
                let _ = self.persist(true, &remaining);
            }
            return Err(error);
        }

        let _ = flush_dns_cache(self.executor.as_ref()).await;
        self.set_snapshot(!remaining.is_empty(), remaining.clone());
        if remaining.is_empty() {
            let _ = self.store.clear();
        } else {
            let _ = self.persist(true, &remaining);
        }
        Ok(())
    }

    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        let _guard = self.op_lock.lock().await;
        self.restore_adapters_impl(adapters).await
    }

    async fn reset_residual_loopback_dns(&self) -> PlatformResult<()> {
        let _guard = self.op_lock.lock().await;
        let result = self.reset_residual_impl().await;

        let (_, mut adapters) = self.snapshot();
        if adapters.is_empty() {
            if let Ok(Some(state)) = self.store.load() {
                adapters = state.adapters;
            }
        }
        if !adapters.is_empty() {
            self.write_restore_script(&adapters);
        }
        result
    }

    fn is_takeover_active(&self) -> bool {
        self.snapshot().0
    }

    fn taken_over_adapters(&self) -> Vec<AdapterState> {
        self.snapshot().1
    }

    async fn flush_dns_cache(&self) -> PlatformResult<()> {
        flush_dns_cache(self.executor.as_ref()).await
    }
}

#[async_trait]
impl Restorer for WindowsDnsManager {
    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        <Self as DnsManager>::restore_adapters(self, adapters).await
    }
}

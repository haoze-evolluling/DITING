//! systemd-resolved backend (`resolvectl dns/domain/revert`).

use diting_desktop_api::platform_types::{AdapterInfo, AdapterState};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::netutil::clean_adapter_state;

use super::{interface_name_from_adapter, interface_name_from_state, merge_dual_stack_servers};

/// Points every adapter at `127.0.0.1`/`::1` and routes all domains through it.
pub(crate) async fn apply(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterInfo],
) -> PlatformResult<()> {
    if adapters.is_empty() {
        return Err(PlatformError::message("无有效网卡可供接管"));
    }

    let mut applied: Vec<String> = Vec::new();
    for adapter in adapters {
        let iface = interface_name_from_adapter(adapter);
        if iface.is_empty() {
            continue;
        }
        if let Err(error) = executor
            .run_checked("resolvectl", &["dns", iface, "127.0.0.1", "::1"])
            .await
        {
            rollback_applied(executor, &applied).await;
            return Err(PlatformError::message(format!(
                "设置网卡 [{iface}] 解析地址失败: {error}"
            )));
        }
        // Register the interface as soon as DNS changed: a failing domain step leaves it in a
        // half-applied state and it must be rolled back too.
        applied.push(iface.to_string());
        if let Err(error) = executor
            .run_checked("resolvectl", &["domain", iface, "~."])
            .await
        {
            rollback_applied(executor, &applied).await;
            return Err(PlatformError::message(format!(
                "设置网卡 [{iface}] 域名路由失败: {error}"
            )));
        }
    }
    Ok(())
}

async fn rollback_applied(executor: &dyn CommandExecutor, interfaces: &[String]) {
    for iface in interfaces {
        let _ = executor.run("resolvectl", &["revert", iface]).await;
    }
}

/// Restores snapshot servers, or reverts to DHCP when the snapshot had none.
pub(crate) async fn restore(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterState],
) -> PlatformResult<()> {
    let mut last_error: Option<PlatformError> = None;
    for raw in adapters {
        let adapter = clean_adapter_state(raw);
        let iface = interface_name_from_state(&adapter);
        if iface.is_empty() {
            continue;
        }

        let servers = merge_dual_stack_servers(&adapter);
        if servers.is_empty() {
            if let Err(error) = executor.run("resolvectl", &["revert", iface]).await {
                last_error = Some(PlatformError::message(format!(
                    "还原网卡 [{iface}] 至自动获取失败: {error}"
                )));
            }
            continue;
        }

        let mut args: Vec<&str> = Vec::with_capacity(servers.len() + 2);
        args.push("dns");
        args.push(iface);
        args.extend(servers.iter().map(String::as_str));
        if let Err(error) = executor.run("resolvectl", &args).await {
            last_error = Some(PlatformError::message(format!(
                "还原网卡 [{iface}] 解析地址失败: {error}"
            )));
            continue;
        }
        let _ = executor.run("resolvectl", &["domain", iface, "~."]).await;
    }
    match last_error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

/// Flushes systemd-resolved caches.
pub(crate) async fn flush(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    executor
        .run_checked("resolvectl", &["flush-caches"])
        .await
        .map(|_| ())
}

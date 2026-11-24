use std::path::Path;

use diting_desktop_api::platform_types::AdapterState;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::linux::dnsstate::{self, RESOLV_CONF_ORIGINAL_PATH};

use super::collect_snapshot_servers;

pub(crate) async fn apply(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if let Ok(content) = dnsstate::read_resolv_conf() {
        if dnsstate::should_preserve_resolv_conf(&content) {
            // 只在首次接管时写备份：重复接管时 resolv.conf 已是回环地址，
            // 覆盖备份会导致还原后指向一个已停止的解析器。
            if !dnsstate::backup_exists("resolv.conf") {
                dnsstate::write_backup_content("resolv.conf", &content).map_err(|error| {
                    PlatformError::message(format!("备份 resolv.conf 失败: {error}"))
                })?;
            }
            if !Path::new(RESOLV_CONF_ORIGINAL_PATH).exists() {
                dnsstate::write_resolv_conf_original(&content).map_err(|error| {
                    PlatformError::message(format!(
                        "备份 /etc/resolv.conf.diting.orig 失败: {error}"
                    ))
                })?;
            }
        }
    }

    dnsstate::record_resolv_conf_symlink()
        .map_err(|error| PlatformError::message(format!("记录 resolv.conf 链接失败: {error}")))?;

    let servers = vec!["127.0.0.1".to_string(), "::1".to_string()];
    dnsstate::write_resolv_conf_atomically(&dnsstate::render_resolv_conf(&servers))?;
    flush(executor).await
}

pub(crate) async fn restore(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterState],
) -> PlatformResult<()> {
    let content = restore_content(adapters);
    dnsstate::restore_resolv_conf(&content)?;
    // 备份必须在还原成功后清理，否则下次接管会复用旧快照而错过新的 DNS 配置。
    dnsstate::clear_backup("resolv.conf");
    let _ = std::fs::remove_file(Path::new(RESOLV_CONF_ORIGINAL_PATH));
    flush(executor).await
}

/// 还原内容优先级：数据目录备份 → 接管前原始文件 → 快照服务器 → 现有非回环服务器。
fn restore_content(adapters: &[AdapterState]) -> String {
    if let Ok(content) = dnsstate::read_backup_content("resolv.conf") {
        if dnsstate::should_preserve_resolv_conf(&content) {
            return content;
        }
    }
    if let Ok(content) = std::fs::read_to_string(RESOLV_CONF_ORIGINAL_PATH) {
        if dnsstate::should_preserve_resolv_conf(&content) {
            return content;
        }
    }
    let servers = collect_snapshot_servers(adapters);
    if !servers.is_empty() {
        return dnsstate::render_resolv_conf(&servers);
    }

    let current = dnsstate::read_resolv_conf().unwrap_or_default();
    let remaining: Vec<String> = dnsstate::parse_resolv_conf(&current)
        .into_iter()
        .filter(|server| !crate::netutil::is_loopback_or_local_ip(server))
        .collect();
    dnsstate::render_resolv_conf(&remaining)
}

pub(crate) async fn flush(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if dnsstate::command_exists("resolvectl") {
        // 尽力而为：systemd-resolved 未运行（例如 WSL 或非 systemd 系统）时，
        // resolvectl 会因 D-Bus 不可用而失败，不应中断接管/还原。
        let _ = executor.run("resolvectl", &["flush-caches"]).await;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::is_residual_loopback_server;

    #[test]
    fn residual_loopback_detection() {
        assert!(is_residual_loopback_server("127.0.0.1"));
        assert!(is_residual_loopback_server("::1"));
        assert!(!is_residual_loopback_server("1.1.1.1"));
    }
}

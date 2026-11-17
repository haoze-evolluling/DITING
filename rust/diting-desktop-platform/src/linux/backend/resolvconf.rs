//! Direct `/etc/resolv.conf` backend for minimal distributions without resolved/NM.

use std::path::Path;

use diting_desktop_api::platform_types::AdapterState;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::linux::dnsstate::{self, RESOLV_CONF_ORIGINAL_PATH};

/// Rewrites `/etc/resolv.conf` to the local resolver, backing up the original first.
pub(crate) async fn apply(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if let Ok(content) = dnsstate::read_resolv_conf() {
        dnsstate::write_backup_content("resolv.conf", &content)
            .map_err(|error| PlatformError::message(format!("备份 resolv.conf 失败: {error}")))?;
        // The offline restore script reads this exact path; it must be written together with the
        // takeover or the script's preferred branch never exists.
        dnsstate::write_resolv_conf_original(&content).map_err(|error| {
            PlatformError::message(format!("备份 /etc/resolv.conf.diting.orig 失败: {error}"))
        })?;
    } else {
        let _ = std::fs::remove_file(RESOLV_CONF_ORIGINAL_PATH);
    }

    let servers = vec!["127.0.0.1".to_string(), "::1".to_string()];
    dnsstate::write_resolv_conf_atomically(&dnsstate::render_resolv_conf(&servers))?;
    flush(executor).await
}

/// Restores the backed-up file, falling back to public resolvers when none exists.
pub(crate) async fn restore(
    executor: &dyn CommandExecutor,
    _adapters: &[AdapterState],
) -> PlatformResult<()> {
    let content = match dnsstate::read_backup_content("resolv.conf") {
        Ok(content) => content,
        Err(_) => {
            let servers = vec!["223.5.5.5".to_string(), "119.29.29.29".to_string()];
            dnsstate::render_resolv_conf(&servers)
        }
    };
    dnsstate::write_resolv_conf_atomically(&content)?;
    // The original is no longer useful after a successful restore and would otherwise be picked
    // up as a stale "older original" by the next takeover.
    let _ = std::fs::remove_file(Path::new(RESOLV_CONF_ORIGINAL_PATH));
    flush(executor).await
}

/// Flushes resolved caches when resolvectl happens to be installed.
pub(crate) async fn flush(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if dnsstate::command_exists("resolvectl") {
        executor
            .run_checked("resolvectl", &["flush-caches"])
            .await
            .map(|_| ())?;
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

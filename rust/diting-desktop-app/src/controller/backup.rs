use std::time::{SystemTime, UNIX_EPOCH};

use diting_desktop_api::config::backup::{self, BackupDocument};

use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default)]
pub struct ImportOutcome {
    /// 备份中实际恢复的配置分节数量。
    pub sections: usize,
    /// 配置已保存但 DNS 监听器未能按新配置重启时的提示。
    pub restart_warning: Option<String>,
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

impl AppRuntime {
    pub fn export_config_backup(&self) -> Result<String, ControllerError> {
        backup::export_document(&self.config(), now_ms())
            .map_err(|error| ControllerError::new(format!("生成配置备份失败: {error}")))
    }

    pub async fn import_config_backup(
        &self,
        document: &BackupDocument,
    ) -> Result<ImportOutcome, ControllerError> {
        let current = self.config();
        let next = backup::resolve(document, &current)
            .map_err(|error| ControllerError::new(error.message()))?;
        let was_running = self.is_dns_running();
        let restart_required =
            was_running && (next.dns != current.dns || next.encrypted != current.encrypted);

        self.update_config(|config| *config = next)
            .map_err(ControllerError::new)?;

        let mut outcome = ImportOutcome {
            sections: document.data.len(),
            restart_warning: None,
        };
        if restart_required {
            outcome.restart_warning = self.restart_dns_after_import().await;
        }
        Ok(outcome)
    }

    /// 导入后重启监听器以应用新的监听地址或加密 DNS 配置，失败时返回提示而不回滚配置。
    async fn restart_dns_after_import(&self) -> Option<String> {
        let takeover = self
            .platform()
            .and_then(|platform| platform.dns_manager.clone())
            .map(|manager| manager.is_takeover_active())
            .unwrap_or(false);
        if let Err(error) = self.stop_dns_checked().await {
            return Some(format!("配置已保存，但停止 DNS 监听器失败: {error}"));
        }
        if let Err(error) = self.start_dns_checked().await {
            return Some(format!(
                "配置已保存，但 DNS 监听器未能按新配置启动: {error}"
            ));
        }
        if takeover {
            if let Err(error) = self.enable_takeover().await {
                return Some(format!("配置已保存，但系统 DNS 接管未能恢复: {error}"));
            }
        }
        None
    }
}

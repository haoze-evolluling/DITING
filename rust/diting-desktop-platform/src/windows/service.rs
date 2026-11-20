use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{
    AutoStartStatus, CoreServiceStatus, AUTO_START_MECHANISM_LOGIN_ITEM, AUTO_START_MECHANISM_NONE,
    AUTO_START_MECHANISM_SERVICE, SERVICE_STATE_NOT_INSTALLED, SERVICE_STATE_RUNNING,
    SERVICE_STATE_START_PENDING, SERVICE_STATE_STOPPED, SERVICE_STATE_STOP_PENDING,
    SERVICE_STATE_UNKNOWN,
};
use windows_sys::Win32::System::Services::{SERVICE_AUTO_START, SERVICE_DISABLED};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::{PrivilegedExecutor, ServiceManager};

use super::adapter_registry::{expand_env, read_machine_string};
use super::autostart::login_item_enabled;
use super::elevate::WindowsPrivilegedExecutor;
use super::service_scm::{
    delete_service_native, install_service_native, query_scm, query_start_type,
    start_service_native, stop_service_native,
};
use super::SERVICE_NAME;

pub struct WindowsServiceManager {
    service_name: String,
    _executor: Arc<dyn CommandExecutor>,
    privileged: Arc<dyn PrivilegedExecutor>,
}

impl WindowsServiceManager {
    pub fn new(
        executor: Arc<dyn CommandExecutor>,
        privileged: Option<Arc<dyn PrivilegedExecutor>>,
    ) -> Self {
        Self {
            service_name: SERVICE_NAME.to_string(),
            _executor: executor,
            privileged: privileged.unwrap_or_else(|| Arc::new(WindowsPrivilegedExecutor::new())),
        }
    }

    fn auto_start_status(&self, installed: bool) -> AutoStartStatus {
        if installed {
            if let Ok(start_type) = query_start_type(&self.service_name) {
                if start_type == SERVICE_AUTO_START {
                    return AutoStartStatus {
                        enabled: true,
                        mechanism: AUTO_START_MECHANISM_SERVICE.to_string(),
                        detail:
                            "已注册为 Windows 系统服务并设为自动启动，开机无需登录即可守护运行。"
                                .to_string(),
                    };
                }
                if start_type == SERVICE_DISABLED {
                    return AutoStartStatus {
                        enabled: false,
                        mechanism: AUTO_START_MECHANISM_NONE.to_string(),
                        detail: "系统服务已被设为禁用启动，开机不会自动运行。".to_string(),
                    };
                }
            }
        }

        if login_item_enabled() {
            return AutoStartStatus {
                enabled: true,
                mechanism: AUTO_START_MECHANISM_LOGIN_ITEM.to_string(),
                detail: "已加入 Windows 用户登录启动项，登录桌面后自动运行。".to_string(),
            };
        }

        if installed {
            return AutoStartStatus {
                enabled: false,
                mechanism: AUTO_START_MECHANISM_NONE.to_string(),
                detail: "系统服务已安装但启动类型为手动，开机不会自动运行。".to_string(),
            };
        }

        AutoStartStatus {
            enabled: false,
            mechanism: AUTO_START_MECHANISM_NONE.to_string(),
            detail: "尚未配置任何开机自启托管机制。".to_string(),
        }
    }
}

#[async_trait]
impl ServiceManager for WindowsServiceManager {
    async fn status(&self) -> PlatformResult<CoreServiceStatus> {
        let mut status = CoreServiceStatus {
            state: SERVICE_STATE_UNKNOWN.to_string(),
            state_text: "未知状态".to_string(),
            is_elevated: self.privileged.is_elevated(),
            ..CoreServiceStatus::default()
        };

        match self.locate_executable().await {
            Ok(path) => {
                status.executable_path = path;
                status.can_install = true;
            }
            Err(_) => status.can_install = false,
        }

        let (installed, running, state) = query_scm(&self.service_name)
            .map_err(|error| PlatformError::message(format!("检测核心服务状态失败: {error}")))?;
        status.installed = installed;
        status.running = running;
        status.state = state.clone();
        status.auto_start = Some(self.auto_start_status(installed));

        let (text, message) = state_text_and_message(&state);
        status.state_text = text.to_string();
        status.message = message.to_string();
        Ok(status)
    }

    async fn start(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() {
            return start_service_native(&self.service_name);
        }
        let exe = self.locate_executable().await?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "start".to_string()])
            .await
    }

    async fn stop(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() {
            return stop_service_native(&self.service_name);
        }
        let exe = self.locate_executable().await?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "stop".to_string()])
            .await
    }

    async fn restart(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() {
            stop_service_native(&self.service_name)?;
            for _ in 0..30 {
                tokio::time::sleep(Duration::from_millis(100)).await;
                let running = query_scm(&self.service_name)
                    .map(|(_, running, _)| running)
                    .unwrap_or(false);
                if !running {
                    break;
                }
            }
            return start_service_native(&self.service_name);
        }
        let exe = self.locate_executable().await?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "restart".to_string()])
            .await
    }

    async fn install(&self, exe_path: &str) -> PlatformResult<()> {
        self.install_with_args(exe_path, &[]).await
    }

    async fn install_and_start(&self, exe_path: &str) -> PlatformResult<()> {
        self.install_and_start_with_args(exe_path, &[]).await
    }

    async fn install_with_args(&self, exe_path: &str, args: &[String]) -> PlatformResult<()> {
        let exe = self.resolve_exe(exe_path).await?;
        if self.privileged.is_elevated() {
            return install_service_native(&self.service_name, &exe, args);
        }
        let mut command = vec!["-service".to_string(), "install".to_string()];
        command.extend(args.iter().cloned());
        self.privileged.run_elevated(&exe, &command).await
    }

    async fn install_and_start_with_args(
        &self,
        exe_path: &str,
        args: &[String],
    ) -> PlatformResult<()> {
        let _ = self.install_with_args(exe_path, args).await;
        self.start().await
    }

    async fn uninstall(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() {
            let _ = stop_service_native(&self.service_name);
            return delete_service_native(&self.service_name);
        }
        let exe = self.locate_executable().await?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "uninstall".to_string()])
            .await
    }

    async fn locate_executable(&self) -> PlatformResult<String> {
        let registry_path = format!(r"SYSTEM\CurrentControlSet\Services\{}", self.service_name);
        if let Some(image_path) = read_machine_string(&registry_path, "ImagePath") {
            let candidate = clean_image_path(&image_path);
            if Path::new(&candidate).exists() {
                return Ok(candidate);
            }
        }

        if let Ok(current) = std::env::current_exe() {
            let directory = current.parent().map(Path::to_path_buf).unwrap_or_default();
            let direct = directory.join("diting-service.exe");
            if direct.exists() {
                return Ok(direct.to_string_lossy().into_owned());
            }
            for candidate in [
                directory
                    .join("build")
                    .join("bin")
                    .join("diting-service.exe"),
                directory
                    .join("..")
                    .join("build")
                    .join("bin")
                    .join("diting-service.exe"),
                directory
                    .join("..")
                    .join("..")
                    .join("build")
                    .join("bin")
                    .join("diting-service.exe"),
            ] {
                if candidate.exists() {
                    return Ok(absolute(&candidate).to_string_lossy().into_owned());
                }
            }
        }

        if let Some(path) = std::env::var_os("PATH") {
            for directory in std::env::split_paths(&path) {
                let candidate = directory.join("diting-service.exe");
                if candidate.exists() {
                    return Ok(absolute(&candidate).to_string_lossy().into_owned());
                }
            }
        }

        Err(PlatformError::message(
            "未找到后台核心服务执行程序 (diting-service.exe)",
        ))
    }
}

impl WindowsServiceManager {
    async fn resolve_exe(&self, exe_path: &str) -> PlatformResult<String> {
        if exe_path.is_empty() {
            self.locate_executable().await
        } else {
            Ok(exe_path.to_string())
        }
    }
}

fn clean_image_path(raw: &str) -> String {
    let expanded = expand_env(raw.trim()).trim_matches('"').to_string();
    if let Some(index) = expanded.to_ascii_lowercase().find(".exe") {
        return expanded[..index + 4].trim_matches('"').to_string();
    }
    expanded.trim_matches('"').to_string()
}

fn absolute(path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .map(|directory| directory.join(path))
            .unwrap_or_else(|_| path.to_path_buf())
    }
}

fn state_text_and_message(state: &str) -> (&'static str, &'static str) {
    match state {
        SERVICE_STATE_RUNNING => ("运行中", "核心服务正常运行中。"),
        SERVICE_STATE_STOPPED => ("已停止", "核心服务已安装，当前处于停止状态。"),
        SERVICE_STATE_START_PENDING => ("正在启动", "核心服务正在启动中..."),
        SERVICE_STATE_STOP_PENDING => ("正在停止", "核心服务正在停止中..."),
        SERVICE_STATE_NOT_INSTALLED => ("未安装", "后台核心服务尚未安装到系统中。"),
        _ => ("已停止", "核心服务未运行。"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn image_path_is_trimmed_to_the_executable() {
        assert_eq!(
            clean_image_path(r#""C:\Program Files\DITING\diting-service.exe" -service run"#),
            r"C:\Program Files\DITING\diting-service.exe"
        );
        assert_eq!(
            clean_image_path(r"C:\DITING\diting-service.exe"),
            r"C:\DITING\diting-service.exe"
        );
    }

    #[test]
    fn state_texts_match_go_messages() {
        assert_eq!(state_text_and_message(SERVICE_STATE_RUNNING).0, "运行中");
        assert_eq!(state_text_and_message(SERVICE_STATE_STOPPED).0, "已停止");
        assert_eq!(
            state_text_and_message(SERVICE_STATE_NOT_INSTALLED).0,
            "未安装"
        );
        assert_eq!(state_text_and_message("weird").0, "已停止");
    }
}

use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{
    AutoStartStatus, CoreServiceStatus, AUTO_START_MECHANISM_NONE, AUTO_START_MECHANISM_PROCD,
    SERVICE_STATE_NOT_INSTALLED, SERVICE_STATE_RUNNING, SERVICE_STATE_STOPPED,
};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::{AutoStartManager, PrivilegedExecutor, ServiceManager};

use super::super::files;
use super::{INIT_SCRIPT_PATH, SERVICE_NAME};

pub struct OpenWrtServiceManager {
    executor: Arc<dyn CommandExecutor>,
    privileged: Arc<dyn PrivilegedExecutor>,
}

impl OpenWrtServiceManager {
    pub fn new(
        executor: Arc<dyn CommandExecutor>,
        privileged: Option<Arc<dyn PrivilegedExecutor>>,
    ) -> Self {
        let privileged = privileged.unwrap_or_else(super::super::new_privileged_executor);
        Self {
            executor,
            privileged,
        }
    }

    async fn is_enabled_via_init(&self) -> bool {
        if !files::file_exists(Path::new(INIT_SCRIPT_PATH)) {
            return false;
        }
        self.executor
            .run(INIT_SCRIPT_PATH, &["enabled"])
            .await
            .is_ok_and(|out| out.success)
    }

    async fn is_running_via_init(&self) -> bool {
        if !files::file_exists(Path::new(INIT_SCRIPT_PATH)) {
            return false;
        }
        if let Ok(out) = self.executor.run(INIT_SCRIPT_PATH, &["running"]).await {
            if out.success {
                return true;
            }
        }
        if let Ok(out) = self.executor.run("pgrep", &["-x", "diting-service"]).await {
            if out.success && !out.text().is_empty() {
                return true;
            }
        }
        false
    }

    async fn run_init(&self, action: &str) -> PlatformResult<()> {
        require_root(action)?;
        if !files::file_exists(Path::new(INIT_SCRIPT_PATH)) {
            return Err(PlatformError::message(format!(
                "未找到 OpenWrt 服务脚本 {INIT_SCRIPT_PATH}，请先安装服务"
            )));
        }
        self.executor
            .run_checked(INIT_SCRIPT_PATH, &[action])
            .await
            .map(|_| ())
            .map_err(|error| {
                PlatformError::message(format!("procd 服务操作 [{action}] 失败: {error}"))
            })
    }
}

fn require_root(action: &str) -> PlatformResult<()> {
    if crate::privilege::is_elevated() {
        return Ok(());
    }
    Err(PlatformError::message(format!(
        "OpenWrt 服务操作 [{action}] 需要 root 权限"
    )))
}

#[async_trait]
impl ServiceManager for OpenWrtServiceManager {
    async fn status(&self) -> PlatformResult<CoreServiceStatus> {
        let installed = files::file_exists(Path::new(INIT_SCRIPT_PATH));
        let exe = self.locate_executable().await.unwrap_or_default();
        let can_install = !exe.is_empty();
        if !installed {
            return Ok(CoreServiceStatus {
                installed: false,
                running: false,
                state: SERVICE_STATE_NOT_INSTALLED.to_string(),
                state_text: "未安装".to_string(),
                executable_path: exe,
                is_elevated: self.privileged.is_elevated(),
                can_install,
                message: "procd 启动脚本 /etc/init.d/diting 尚未安装。".to_string(),
                auto_start: Some(AutoStartStatus {
                    enabled: false,
                    mechanism: AUTO_START_MECHANISM_NONE.to_string(),
                    detail: "未注册 procd 开机自启。".to_string(),
                }),
            });
        }

        let running = self.is_running_via_init().await;
        let enabled = self.is_enabled_via_init().await;
        let (state, state_text, message) = if running {
            (
                SERVICE_STATE_RUNNING.to_string(),
                "运行中".to_string(),
                "由 OpenWrt procd 守护运行中（崩溃自动拉起）。".to_string(),
            )
        } else {
            (
                SERVICE_STATE_STOPPED.to_string(),
                "已停止".to_string(),
                format!("服务已安装但未运行，可执行 {INIT_SCRIPT_PATH} start 启动。"),
            )
        };
        let auto_start = if enabled {
            AutoStartStatus {
                enabled: true,
                mechanism: AUTO_START_MECHANISM_PROCD.to_string(),
                detail: "已通过 /etc/rc.d 注册 procd 开机自启。".to_string(),
            }
        } else {
            AutoStartStatus {
                enabled: false,
                mechanism: AUTO_START_MECHANISM_NONE.to_string(),
                detail: "procd 自启已关闭（执行 /etc/init.d/diting enable 开启）。".to_string(),
            }
        };

        Ok(CoreServiceStatus {
            installed: true,
            running,
            state,
            state_text,
            executable_path: exe,
            is_elevated: self.privileged.is_elevated(),
            can_install,
            message,
            auto_start: Some(auto_start),
        })
    }

    async fn start(&self) -> PlatformResult<()> {
        self.run_init("start").await
    }

    async fn stop(&self) -> PlatformResult<()> {
        self.run_init("stop").await
    }

    async fn restart(&self) -> PlatformResult<()> {
        self.run_init("restart").await
    }

    async fn install(&self, exe_path: &str) -> PlatformResult<()> {
        self.install_with_args(exe_path, &[]).await
    }

    async fn install_and_start(&self, exe_path: &str) -> PlatformResult<()> {
        self.install_and_start_with_args(exe_path, &[]).await
    }

    async fn install_with_args(&self, exe_path: &str, args: &[String]) -> PlatformResult<()> {
        require_root("install")?;
        let resolved = if exe_path.is_empty() {
            self.locate_executable().await?
        } else {
            exe_path.to_string()
        };
        let script = render_procd_init_script(&resolved, args);
        files::write_file_mode(Path::new(INIT_SCRIPT_PATH), script.as_bytes(), 0o755).map_err(
            |error| PlatformError::message(format!("写入 {INIT_SCRIPT_PATH} 失败: {error}")),
        )?;
        self.run_init("enable").await
    }

    async fn install_and_start_with_args(
        &self,
        exe_path: &str,
        args: &[String],
    ) -> PlatformResult<()> {
        self.install_with_args(exe_path, args).await?;
        self.start().await
    }

    async fn uninstall(&self) -> PlatformResult<()> {
        require_root("uninstall")?;
        let _ = self.executor.run(INIT_SCRIPT_PATH, &["stop"]).await;
        let _ = self.executor.run(INIT_SCRIPT_PATH, &["disable"]).await;
        files::remove_file_if_exists(Path::new(INIT_SCRIPT_PATH)).map_err(|error| {
            PlatformError::message(format!("删除 {INIT_SCRIPT_PATH} 失败: {error}"))
        })
    }

    async fn locate_executable(&self) -> PlatformResult<String> {
        for candidate in [
            "/usr/bin/diting-service",
            "/usr/sbin/diting-service",
            "/usr/local/bin/diting-service",
            "/opt/diting/diting-service",
        ] {
            if files::file_exists(Path::new(candidate)) {
                return Ok(candidate.to_string());
            }
        }
        if let Ok(exe) = std::env::current_exe() {
            return Ok(exe.to_string_lossy().into_owned());
        }
        Err(PlatformError::message("未找到 diting-service 可执行文件"))
    }
}

pub fn render_procd_init_script(executable: &str, args: &[String]) -> String {
    let mut cmd = format!("{} -run", shell_quote(executable));
    for arg in args {
        cmd.push(' ');
        cmd.push_str(&shell_quote(arg));
    }
    format!(
        "#!/bin/sh /etc/rc.common\n\
         # 谛听 (DITING) OpenWrt procd 服务脚本\n\
         START=95\n\
         STOP=10\n\
         USE_PROCD=1\n\
         PROG={exe}\n\n\
         start_service() {{\n\
             mkdir -p /etc/diting /tmp/diting\n\
             procd_open_instance {SERVICE_NAME}\n\
             procd_set_param command {cmd}\n\
             procd_set_param respawn ${{respawn_threshold:-3600}} ${{respawn_timeout:-5}} ${{respawn_retry:-5}}\n\
             procd_set_param limits nofile=\"65536 65536\"\n\
             procd_set_param stdout 1\n\
             procd_set_param stderr 1\n\
             procd_close_instance\n\
         }}\n",
        exe = shell_quote(executable),
    )
}

fn shell_quote(value: &str) -> String {
    if value
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '/' | '-' | '_' | '.' | ':'))
    {
        return value.to_string();
    }
    format!("'{}'", value.replace('\'', "'\\''"))
}

pub struct OpenWrtAutoStart;

impl OpenWrtAutoStart {
    pub fn new() -> Self {
        Self
    }
}

impl Default for OpenWrtAutoStart {
    fn default() -> Self {
        Self::new()
    }
}

impl AutoStartManager for OpenWrtAutoStart {
    fn is_enabled(&self) -> bool {
        rc_symlink_exists()
    }

    fn set_enabled(&self, enable: bool) -> PlatformResult<AutoStartStatus> {
        require_root("autostart")?;
        let action = if enable { "enable" } else { "disable" };
        let status = std::process::Command::new(INIT_SCRIPT_PATH)
            .arg(action)
            .status()
            .map_err(PlatformError::from)?;
        if !status.success() {
            return Err(PlatformError::message(format!(
                "执行 {INIT_SCRIPT_PATH} {action} 失败"
            )));
        }
        Ok(AutoStartStatus {
            enabled: enable,
            mechanism: if enable {
                AUTO_START_MECHANISM_PROCD.to_string()
            } else {
                AUTO_START_MECHANISM_NONE.to_string()
            },
            detail: if enable {
                "已启用 procd 开机自启。".to_string()
            } else {
                "已禁用 procd 开机自启。".to_string()
            },
        })
    }
}

fn rc_symlink_exists() -> bool {
    let Ok(entries) = std::fs::read_dir("/etc/rc.d") else {
        return false;
    };
    entries
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .any(|name| name.starts_with('S') && name.ends_with(SERVICE_NAME))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_valid_procd_init_script() {
        let script = render_procd_init_script(
            "/usr/bin/diting-service",
            &["-ipc-addr".into(), "0.0.0.0:15353".into()],
        );
        assert!(script.starts_with("#!/bin/sh /etc/rc.common"));
        assert!(script.contains("USE_PROCD=1"));
        assert!(script.contains(
            "procd_set_param command /usr/bin/diting-service -run -ipc-addr 0.0.0.0:15353"
        ));
        assert!(script.contains("procd_set_param respawn"));
    }
}

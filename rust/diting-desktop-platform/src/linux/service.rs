//! systemd unit management for the privileged core service (`diting-dnsservice`).

use std::path::{Path, PathBuf};
use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{
    AutoStartStatus, CoreServiceStatus, AUTO_START_MECHANISM_NONE, AUTO_START_MECHANISM_SYSTEMD,
    AUTO_START_MECHANISM_XDG, SERVICE_STATE_NOT_INSTALLED, SERVICE_STATE_RUNNING,
    SERVICE_STATE_START_PENDING, SERVICE_STATE_STOPPED, SERVICE_STATE_STOP_PENDING,
    SERVICE_STATE_UNKNOWN,
};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::{PrivilegedExecutor, ServiceManager};

use super::{autostart, dnsstate, files, SERVICE_DISPLAY_NAME, SERVICE_NAME};

const UNIT_NAME: &str = "diting-dnsservice.service";
const UNIT_PATH: &str = "/etc/systemd/system/diting-dnsservice.service";

/// Parsed subset of `systemctl show` fields.
#[derive(Debug, Default, Clone)]
struct ServiceStatus {
    load_state: String,
    active_state: String,
    sub_state: String,
    unit_file_state: String,
}

/// systemd-backed service lifecycle manager.
pub struct LinuxServiceManager {
    executor: Arc<dyn CommandExecutor>,
    privileged: Arc<dyn PrivilegedExecutor>,
}

impl LinuxServiceManager {
    pub fn new(
        executor: Arc<dyn CommandExecutor>,
        privileged: Option<Arc<dyn PrivilegedExecutor>>,
    ) -> Self {
        let privileged = privileged.unwrap_or_else(super::new_privileged_executor);
        Self {
            executor,
            privileged,
        }
    }

    fn auto_start_status(&self, status: &ServiceStatus) -> AutoStartStatus {
        if status.unit_file_state == "enabled" {
            return AutoStartStatus {
                enabled: true,
                mechanism: AUTO_START_MECHANISM_SYSTEMD.to_string(),
                detail: "systemd 单元已 enable，开机无需登录即可守护运行。".to_string(),
            };
        }
        if status.unit_file_state == "masked" || status.unit_file_state == "disabled" {
            return AutoStartStatus {
                enabled: false,
                mechanism: AUTO_START_MECHANISM_NONE.to_string(),
                detail: "systemd 单元已被 disable/mask，开机不会自动运行。".to_string(),
            };
        }
        if autostart::xdg_auto_start_present() {
            return AutoStartStatus {
                enabled: true,
                mechanism: AUTO_START_MECHANISM_XDG.to_string(),
                detail: "已加入 XDG 桌面登录自启条目，登录桌面后自动运行。".to_string(),
            };
        }
        AutoStartStatus {
            enabled: false,
            mechanism: AUTO_START_MECHANISM_NONE.to_string(),
            detail: "尚未配置任何开机自启托管机制。".to_string(),
        }
    }

    async fn executable_from_unit(&self) -> Option<String> {
        // Through the executor: `systemctl` may block (D-Bus, slow host), so it must not run on a
        // runtime worker thread.
        let output = self
            .executor
            .run("systemctl", &["show", UNIT_NAME, "-p", "ExecStart", "--value"])
            .await
            .ok()?;
        if !output.success {
            return None;
        }
        let text = output.text();
        let path = parse_exec_start_path(&text);
        if path.is_empty() {
            None
        } else {
            Some(path)
        }
    }

    async fn control(&self, action: &str) -> PlatformResult<()> {
        require_root("服务控制")?;
        self.executor
            .run_checked("systemctl", &[action, SERVICE_NAME])
            .await
            .map(|_| ())
            .map_err(|error| {
                PlatformError::message(format!("服务控制操作 [{action}] 失败: {error}"))
            })
    }
}

#[async_trait]
impl ServiceManager for LinuxServiceManager {
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

        let output = self
            .executor
            .run(
                "systemctl",
                &[
                    "show",
                    UNIT_NAME,
                    "-p",
                    "LoadState,ActiveState,SubState,UnitFileState",
                ],
            )
            .await
            .map_err(|error| PlatformError::message(format!("检测核心服务状态失败: {error}")))?;
        if !output.success {
            return Err(PlatformError::message(format!(
                "检测核心服务状态失败: {}",
                output.text()
            )));
        }

        let parsed = parse_systemctl_show(&output.text());
        apply_service_status(&mut status, &parsed);
        status.auto_start = Some(self.auto_start_status(&parsed));
        Ok(status)
    }

    async fn start(&self) -> PlatformResult<()> {
        self.control("start").await
    }

    async fn stop(&self) -> PlatformResult<()> {
        self.control("stop").await
    }

    async fn restart(&self) -> PlatformResult<()> {
        self.control("restart").await
    }

    async fn install(&self, exe_path: &str) -> PlatformResult<()> {
        require_root("安装服务")?;
        let exe_path = if exe_path.is_empty() {
            self.locate_executable().await?
        } else {
            exe_path.to_string()
        };

        let unit = render_systemd_unit(&abs_executable_path(&exe_path));
        files::write_file_mode(Path::new(UNIT_PATH), unit.as_bytes(), 0o644)
            .map_err(|error| PlatformError::message(format!("写入 systemd 单元失败: {error}")))?;
        self.executor
            .run_checked("systemctl", &["daemon-reload"])
            .await
            .map_err(|error| PlatformError::message(format!("重载 systemd 配置失败: {error}")))?;
        self.executor
            .run_checked("systemctl", &["enable", SERVICE_NAME])
            .await
            .map_err(|error| PlatformError::message(format!("设置开机自启失败: {error}")))?;
        Ok(())
    }

    async fn install_and_start(&self, exe_path: &str) -> PlatformResult<()> {
        // An already-installed unit must not prevent the subsequent start attempt.
        let _ = self.install(exe_path).await;
        self.start().await
    }

    async fn uninstall(&self) -> PlatformResult<()> {
        require_root("卸载服务")?;
        let _ = self
            .executor
            .run("systemctl", &["stop", SERVICE_NAME])
            .await;
        let _ = self
            .executor
            .run("systemctl", &["disable", SERVICE_NAME])
            .await;

        files::remove_file_if_exists(Path::new(UNIT_PATH))
            .map_err(|error| PlatformError::message(format!("删除 systemd 单元失败: {error}")))?;
        let _ = self.executor.run("systemctl", &["daemon-reload"]).await;
        Ok(())
    }

    async fn locate_executable(&self) -> PlatformResult<String> {
        if let Some(path) = self.executable_from_unit().await {
            if files::file_exists(Path::new(&path)) {
                return Ok(path);
            }
        }

        for candidate in [
            "/usr/local/bin/diting-service",
            "/usr/bin/diting-service",
            "/opt/diting/diting-service",
            "./build/bin/diting-service",
            "build/bin/diting-service",
        ] {
            if files::file_exists(Path::new(candidate)) {
                // systemd resolves ExecStart against `/`, so relative candidates must be absolute.
                return Ok(abs_executable_path(candidate));
            }
        }

        if dnsstate::command_exists("diting-service") {
            if let Some(resolved) = find_in_path("diting-service") {
                return Ok(abs_executable_path(&resolved.to_string_lossy()));
            }
            return Ok(abs_executable_path("diting-service"));
        }

        // On Linux the running binary is reachable through /proc/self/exe.
        if let Ok(executable) = std::env::current_exe() {
            return Ok(abs_executable_path(&executable.to_string_lossy()));
        }

        Err(PlatformError::message("未找到 diting-service 可执行文件"))
    }
}

fn require_root(operation: &str) -> PlatformResult<()> {
    if crate::privilege::is_elevated() {
        return Ok(());
    }
    Err(PlatformError::message(format!(
        "{operation} 需要 root 权限，请使用 sudo 重试: 当前权限不足，请以 root 身份重新运行（例如 sudo diting-service）"
    )))
}

fn find_in_path(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        let path = PathBuf::from(name);
        return path.is_file().then_some(path);
    }
    let path = std::env::var_os("PATH")?;
    for directory in std::env::split_paths(&path) {
        if directory.as_os_str().is_empty() {
            continue;
        }
        let candidate = directory.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn abs_executable_path(path: &str) -> String {
    if path.is_empty() || Path::new(path).is_absolute() {
        return path.to_string();
    }
    match std::env::current_dir() {
        Ok(directory) => directory.join(path).to_string_lossy().into_owned(),
        Err(_) => path.to_string(),
    }
}

/// Parses the executable path out of a structured `ExecStart` value.
fn parse_exec_start_path(output: &str) -> String {
    let trimmed = output.trim();
    if trimmed.is_empty() || trimmed == "unknown" {
        return String::new();
    }
    if let Some(index) = trimmed.find("path=") {
        let rest = &trimmed[index + "path=".len()..];
        let rest = match rest.find(' ') {
            Some(end) => &rest[..end],
            None => rest,
        };
        return rest.trim_matches(';').to_string();
    }
    trimmed.split_whitespace().next().unwrap_or("").to_string()
}

/// Parses `systemctl show` Key=Value output.
fn parse_systemctl_show(output: &str) -> ServiceStatus {
    let mut status = ServiceStatus::default();
    for line in output.split('\n') {
        let Some((key, value)) = line.trim().split_once('=') else {
            continue;
        };
        match key {
            "LoadState" => status.load_state = value.to_string(),
            "ActiveState" => status.active_state = value.to_string(),
            "SubState" => status.sub_state = value.to_string(),
            "UnitFileState" => status.unit_file_state = value.to_string(),
            _ => {}
        }
    }
    status
}

fn apply_service_status(status: &mut CoreServiceStatus, parsed: &ServiceStatus) {
    if parsed.load_state == "not-found" || parsed.load_state.is_empty() {
        status.installed = false;
        status.running = false;
        status.state = SERVICE_STATE_NOT_INSTALLED.to_string();
        status.state_text = "未安装".to_string();
        status.message = "后台核心服务尚未安装到系统中。".to_string();
        return;
    }

    status.installed = true;
    status.running = parsed.active_state == "active";

    match parsed.active_state.as_str() {
        "active" => {
            status.state = SERVICE_STATE_RUNNING.to_string();
            status.state_text = "运行中".to_string();
            status.message = "核心服务正常运行中。".to_string();
        }
        "activating" => {
            status.state = SERVICE_STATE_START_PENDING.to_string();
            status.state_text = "正在启动".to_string();
            status.message = "核心服务正在启动中...".to_string();
        }
        "deactivating" => {
            status.state = SERVICE_STATE_STOP_PENDING.to_string();
            status.state_text = "正在停止".to_string();
            status.message = "核心服务正在停止中...".to_string();
        }
        "failed" => {
            status.state = SERVICE_STATE_STOPPED.to_string();
            status.state_text = "已停止".to_string();
            status.message =
                format!("核心服务运行失败，请执行 journalctl -u {SERVICE_NAME} 查看日志。");
        }
        _ => {
            status.state = SERVICE_STATE_STOPPED.to_string();
            status.state_text = "已停止".to_string();
            status.message = "核心服务已安装，当前处于停止状态。".to_string();
        }
    }
}

fn render_systemd_unit(executable: &str) -> String {
    format!(
        "[Unit]\nDescription={SERVICE_DISPLAY_NAME}\nDocumentation=https://github.com/haoze-evolluling/diting\nAfter=syslog.target network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart={executable} -run\nRestart=always\nRestartSec=10\nLimitNOFILE=65536\nStandardOutput=journal\nStandardError=journal\n\n[Install]\nWantedBy=multi-user.target\n"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn systemctl_show_is_parsed() {
        let parsed = parse_systemctl_show(
            "LoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\n",
        );
        assert_eq!(parsed.load_state, "loaded");
        assert_eq!(parsed.active_state, "active");
        assert_eq!(parsed.sub_state, "running");
        assert_eq!(parsed.unit_file_state, "enabled");
    }

    #[test]
    fn exec_start_path_is_extracted() {
        assert_eq!(
            parse_exec_start_path(
                "{ path=/usr/local/bin/diting-service ; argv[]=/usr/local/bin/diting-service -run ; ignore_errors=no }"
            ),
            "/usr/local/bin/diting-service"
        );
        assert_eq!(
            parse_exec_start_path("/opt/diting/diting-service -run"),
            "/opt/diting/diting-service"
        );
        assert_eq!(parse_exec_start_path(""), "");
        assert_eq!(parse_exec_start_path("unknown"), "");
    }

    #[test]
    fn service_states_map_to_cross_platform_values() {
        let cases = [
            (
                ServiceStatus {
                    load_state: "not-found".into(),
                    ..Default::default()
                },
                false,
                false,
                "not_installed",
            ),
            (
                ServiceStatus {
                    load_state: "loaded".into(),
                    active_state: "active".into(),
                    ..Default::default()
                },
                true,
                true,
                "running",
            ),
            (
                ServiceStatus {
                    load_state: "loaded".into(),
                    active_state: "inactive".into(),
                    ..Default::default()
                },
                true,
                false,
                "stopped",
            ),
            (
                ServiceStatus {
                    load_state: "loaded".into(),
                    active_state: "failed".into(),
                    ..Default::default()
                },
                true,
                false,
                "stopped",
            ),
            (
                ServiceStatus {
                    load_state: "loaded".into(),
                    active_state: "activating".into(),
                    ..Default::default()
                },
                true,
                false,
                "start_pending",
            ),
        ];
        for (parsed, installed, running, state) in cases {
            let mut status = CoreServiceStatus::default();
            apply_service_status(&mut status, &parsed);
            assert_eq!(status.installed, installed);
            assert_eq!(status.running, running);
            assert_eq!(status.state, state);
        }
    }
}

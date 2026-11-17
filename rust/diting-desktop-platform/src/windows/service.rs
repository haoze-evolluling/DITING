//! Windows service lifecycle for the privileged DNS core.
//!
//! Status queries go straight to the SCM. Mutations try the native SCM path when the process is
//! already elevated and otherwise re-launch the service executable with `-service <verb>`, which
//! triggers UAC. This mirrors the Go manager and keeps one binary as both service host and CLI.

use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{
    AutoStartStatus, CoreServiceStatus, AUTO_START_MECHANISM_LOGIN_ITEM, AUTO_START_MECHANISM_NONE,
    AUTO_START_MECHANISM_SERVICE, SERVICE_STATE_NOT_INSTALLED, SERVICE_STATE_RUNNING,
    SERVICE_STATE_START_PENDING, SERVICE_STATE_STOPPED, SERVICE_STATE_STOP_PENDING,
    SERVICE_STATE_UNKNOWN,
};
use windows_sys::Win32::Foundation::{
    GetLastError, ERROR_INSUFFICIENT_BUFFER, ERROR_SERVICE_ALREADY_RUNNING,
    ERROR_SERVICE_DOES_NOT_EXIST, ERROR_SERVICE_NOT_ACTIVE,
};
use windows_sys::Win32::System::Services::{
    CloseServiceHandle, ControlService, DeleteService, OpenSCManagerW, OpenServiceW,
    QueryServiceConfigW, QueryServiceStatus, StartServiceW, QUERY_SERVICE_CONFIGW, SC_HANDLE,
    SC_MANAGER_CONNECT, SERVICE_AUTO_START, SERVICE_CONTROL_STOP, SERVICE_DISABLED,
    SERVICE_QUERY_CONFIG, SERVICE_QUERY_STATUS, SERVICE_RUNNING, SERVICE_START,
    SERVICE_START_PENDING, SERVICE_STATUS, SERVICE_STOP, SERVICE_STOPPED, SERVICE_STOP_PENDING,
};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::{PrivilegedExecutor, ServiceManager};

use super::adapter_registry::{expand_env, read_machine_string};
use super::autostart::login_item_enabled;
use super::elevate::WindowsPrivilegedExecutor;
use super::SERVICE_NAME;

/// `DELETE` access right (0x00010000), used to remove a service object.
const SERVICE_DELETE_ACCESS: u32 = 0x0001_0000;

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
        // SCM auto-start runs before any user signs in, so it outranks login items.
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
                    // An explicitly disabled service will not run even if a login item exists.
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

        match self.locate_executable() {
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
        if self.privileged.is_elevated() && start_service_native(&self.service_name).is_ok() {
            return Ok(());
        }
        let exe = self.locate_executable()?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "start".to_string()])
            .await
    }

    async fn stop(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() && stop_service_native(&self.service_name).is_ok() {
            return Ok(());
        }
        let exe = self.locate_executable()?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "stop".to_string()])
            .await
    }

    async fn restart(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() {
            if let Err(error) = stop_service_native(&self.service_name) {
                // A failed stop must surface immediately: waiting three seconds and starting a
                // half-stopped service only hides the root cause.
                return Err(PlatformError::message(format!("停止核心服务失败: {error}")));
            }
            for _ in 0..30 {
                tokio::time::sleep(Duration::from_millis(100)).await;
                let running = query_scm(&self.service_name)
                    .map(|(_, running, _)| running)
                    .unwrap_or(false);
                if !running {
                    break;
                }
            }
            if start_service_native(&self.service_name).is_ok() {
                return Ok(());
            }
        }
        let exe = self.locate_executable()?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "restart".to_string()])
            .await
    }

    async fn install(&self, exe_path: &str) -> PlatformResult<()> {
        let exe = self.resolve_exe(exe_path)?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "install".to_string()])
            .await
    }

    async fn install_and_start(&self, exe_path: &str) -> PlatformResult<()> {
        // If already installed the install verb fails; starting is still the desired outcome.
        let _ = self.install(exe_path).await;
        self.start().await
    }

    async fn uninstall(&self) -> PlatformResult<()> {
        if self.privileged.is_elevated() {
            let _ = stop_service_native(&self.service_name);
            if let Ok(exe) = self.locate_executable() {
                let _ = self
                    .privileged
                    .run_elevated(&exe, &["-service".to_string(), "uninstall".to_string()])
                    .await;
            }
            return delete_service_native(&self.service_name);
        }
        let exe = self.locate_executable()?;
        self.privileged
            .run_elevated(&exe, &["-service".to_string(), "uninstall".to_string()])
            .await
    }

    fn locate_executable(&self) -> PlatformResult<String> {
        // 1. An already-registered service knows its exact ImagePath.
        let registry_path = format!(r"SYSTEM\CurrentControlSet\Services\{}", self.service_name);
        if let Some(image_path) = read_machine_string(&registry_path, "ImagePath") {
            let candidate = clean_image_path(&image_path);
            if Path::new(&candidate).exists() {
                return Ok(candidate);
            }
        }

        // 2. Next to the GUI, then the usual build output directories.
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

        // 3. PATH.
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
    fn resolve_exe(&self, exe_path: &str) -> PlatformResult<String> {
        if exe_path.is_empty() {
            self.locate_executable()
        } else {
            Ok(exe_path.to_string())
        }
    }
}

/// Extracts the executable from a registry `ImagePath`, which may include quotes, environment
/// variables, and trailing service arguments.
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

fn last_error() -> u32 {
    unsafe { GetLastError() }
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

fn open_scm() -> PlatformResult<SC_HANDLE> {
    // SAFETY: null machine/database means the local SCM; the handle is returned to the caller.
    let scm = unsafe { OpenSCManagerW(ptr::null(), ptr::null(), SC_MANAGER_CONNECT) };
    if scm.is_null() {
        Err(PlatformError::message(format!(
            "打开服务控制管理器失败: Windows 错误码 {}",
            last_error()
        )))
    } else {
        Ok(scm)
    }
}

fn open_service(scm: SC_HANDLE, service_name: &str, access: u32) -> PlatformResult<SC_HANDLE> {
    let name = wide(service_name);
    // SAFETY: `scm` is valid and `name` is NUL-terminated.
    let service = unsafe { OpenServiceW(scm, name.as_ptr(), access) };
    if service.is_null() {
        Err(PlatformError::message(format!(
            "打开服务 [{service_name}] 失败: Windows 错误码 {}",
            last_error()
        )))
    } else {
        Ok(service)
    }
}

fn query_start_type(service_name: &str) -> PlatformResult<u32> {
    let scm = open_scm()?;
    let service = match open_service(scm, service_name, SERVICE_QUERY_CONFIG) {
        Ok(service) => service,
        Err(error) => {
            unsafe { CloseServiceHandle(scm) };
            return Err(error);
        }
    };

    let mut needed = 0u32;
    // SAFETY: the first call only asks for the required size.
    unsafe {
        QueryServiceConfigW(service, ptr::null_mut(), 0, &mut needed);
        let error = GetLastError();
        if error != ERROR_INSUFFICIENT_BUFFER || needed == 0 {
            CloseServiceHandle(service);
            CloseServiceHandle(scm);
            return Err(PlatformError::message(format!(
                "服务配置查询未返回所需缓冲区大小: Windows 错误码 {error}"
            )));
        }
        let mut buffer = vec![0u8; needed as usize];
        let result = QueryServiceConfigW(
            service,
            buffer.as_mut_ptr() as *mut QUERY_SERVICE_CONFIGW,
            needed,
            &mut needed,
        );
        if result == 0 {
            let error = GetLastError();
            CloseServiceHandle(service);
            CloseServiceHandle(scm);
            return Err(PlatformError::message(format!(
                "查询服务配置失败: Windows 错误码 {error}"
            )));
        }
        let config = ptr::read_unaligned(buffer.as_ptr() as *const QUERY_SERVICE_CONFIGW);
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
        Ok(config.dwStartType)
    }
}

fn query_scm(service_name: &str) -> PlatformResult<(bool, bool, String)> {
    let scm = open_scm()?;
    let name = wide(service_name);
    // SAFETY: `scm` is valid and `name` is NUL-terminated.
    let service = unsafe { OpenServiceW(scm, name.as_ptr(), SERVICE_QUERY_STATUS) };
    unsafe { CloseServiceHandle(scm) };
    if service.is_null() {
        let error = last_error();
        if error == ERROR_SERVICE_DOES_NOT_EXIST {
            return Ok((false, false, SERVICE_STATE_NOT_INSTALLED.to_string()));
        }
        return Err(PlatformError::message(format!(
            "打开服务 [{service_name}] 失败: Windows 错误码 {error}"
        )));
    }

    let mut status: SERVICE_STATUS = unsafe { std::mem::zeroed() };
    // SAFETY: `service` is valid and `status` is a valid out-pointer.
    let result = unsafe { QueryServiceStatus(service, &mut status) };
    unsafe { CloseServiceHandle(service) };
    if result == 0 {
        return Err(PlatformError::message(format!(
            "查询服务 [{service_name}] 状态失败: Windows 错误码 {}",
            last_error()
        )));
    }

    let state = match status.dwCurrentState {
        SERVICE_RUNNING => SERVICE_STATE_RUNNING,
        SERVICE_STOPPED => SERVICE_STATE_STOPPED,
        SERVICE_START_PENDING => SERVICE_STATE_START_PENDING,
        SERVICE_STOP_PENDING => SERVICE_STATE_STOP_PENDING,
        _ => SERVICE_STATE_STOPPED,
    };
    Ok((
        true,
        status.dwCurrentState == SERVICE_RUNNING,
        state.to_string(),
    ))
}

fn start_service_native(service_name: &str) -> PlatformResult<()> {
    let scm = open_scm()?;
    let service = match open_service(scm, service_name, SERVICE_START) {
        Ok(service) => service,
        Err(error) => {
            unsafe { CloseServiceHandle(scm) };
            return Err(error);
        }
    };
    // SAFETY: no service arguments are passed.
    let result = unsafe { StartServiceW(service, 0, ptr::null()) };
    let error = last_error();
    unsafe {
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
    }
    if result == 0 && error != ERROR_SERVICE_ALREADY_RUNNING {
        return Err(PlatformError::message(format!(
            "启动服务 [{service_name}] 失败: Windows 错误码 {error}"
        )));
    }
    Ok(())
}

fn stop_service_native(service_name: &str) -> PlatformResult<()> {
    let scm = open_scm()?;
    let service = match open_service(scm, service_name, SERVICE_STOP | SERVICE_QUERY_STATUS) {
        Ok(service) => service,
        Err(error) => {
            unsafe { CloseServiceHandle(scm) };
            return Err(error);
        }
    };
    let mut status: SERVICE_STATUS = unsafe { std::mem::zeroed() };
    // SAFETY: `service` is valid and `status` is a valid out-pointer.
    let result = unsafe { ControlService(service, SERVICE_CONTROL_STOP, &mut status) };
    let error = last_error();
    unsafe {
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
    }
    if result == 0 && error != ERROR_SERVICE_NOT_ACTIVE {
        return Err(PlatformError::message(format!(
            "停止服务 [{service_name}] 失败: Windows 错误码 {error}"
        )));
    }
    Ok(())
}

fn delete_service_native(service_name: &str) -> PlatformResult<()> {
    let scm = open_scm()?;
    let name = wide(service_name);
    // SAFETY: `scm` and `name` are valid.
    let service = unsafe { OpenServiceW(scm, name.as_ptr(), SERVICE_DELETE_ACCESS) };
    if service.is_null() {
        let error = last_error();
        unsafe { CloseServiceHandle(scm) };
        if error == ERROR_SERVICE_DOES_NOT_EXIST {
            return Ok(());
        }
        return Err(PlatformError::message(format!(
            "删除服务 [{service_name}] 失败: Windows 错误码 {error}"
        )));
    }
    // SAFETY: `service` is valid; the handle is closed afterwards.
    let result = unsafe { DeleteService(service) };
    let error = last_error();
    unsafe {
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
    }
    if result == 0 {
        return Err(PlatformError::message(format!(
            "删除服务 [{service_name}] 失败: Windows 错误码 {error}"
        )));
    }
    Ok(())
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

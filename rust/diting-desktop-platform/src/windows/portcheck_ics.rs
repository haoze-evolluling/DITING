use std::mem::size_of;
use std::ptr;
use std::time::{Duration, Instant};

use windows_sys::Win32::Foundation::GetLastError;
use windows_sys::Win32::System::Services::{
    ChangeServiceConfigW, CloseServiceHandle, ControlService, OpenSCManagerW, OpenServiceW,
    QueryServiceStatusEx, SC_MANAGER_CONNECT, SC_STATUS_PROCESS_INFO, SERVICE_CHANGE_CONFIG,
    SERVICE_CONTROL_STOP, SERVICE_DISABLED, SERVICE_NO_CHANGE, SERVICE_QUERY_STATUS,
    SERVICE_RUNNING, SERVICE_STATUS, SERVICE_STATUS_PROCESS, SERVICE_STOP, SERVICE_STOPPED,
};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;

fn check_ics_status_native() -> PlatformResult<(bool, u32)> {
    unsafe {
        let scm = OpenSCManagerW(ptr::null(), ptr::null(), SC_MANAGER_CONNECT);
        if scm.is_null() {
            return Err(PlatformError::message(format!(
                "打开服务控制管理器 (SCM) 失败: {}",
                GetLastError()
            )));
        }
        let name: Vec<u16> = "SharedAccess\0".encode_utf16().collect();
        let service = OpenServiceW(scm, name.as_ptr(), SERVICE_QUERY_STATUS);
        CloseServiceHandle(scm);
        if service.is_null() {
            return Ok((false, 0));
        }

        let mut status: SERVICE_STATUS_PROCESS = std::mem::zeroed();
        let mut needed = 0u32;
        let result = QueryServiceStatusEx(
            service,
            SC_STATUS_PROCESS_INFO,
            &mut status as *mut _ as *mut u8,
            size_of::<SERVICE_STATUS_PROCESS>() as u32,
            &mut needed,
        );
        CloseServiceHandle(service);
        if result == 0 {
            return Err(PlatformError::message(format!(
                "查询 SharedAccess 服务状态失败: {}",
                GetLastError()
            )));
        }
        if status.dwCurrentState == SERVICE_RUNNING {
            Ok((true, status.dwProcessId))
        } else {
            Ok((false, 0))
        }
    }
}

pub(crate) fn parse_sc_queryex(output: &str) -> (bool, u32) {
    let mut running = false;
    let mut pid = 0u32;
    for raw_line in output.lines() {
        let line = raw_line.trim();
        let lower = line.to_ascii_lowercase();
        if (lower.starts_with("state") || line.starts_with("状态"))
            && (lower.contains("running")
                || line.contains("正在运行")
                || line.split_whitespace().any(|token| token == "4"))
        {
            running = true;
        }
        if let Some(index) = line.find("PID") {
            if let Some(value) = line[index + 3..]
                .split_whitespace()
                .find_map(|token| token.parse::<u32>().ok())
            {
                pid = value;
            }
        }
    }
    (running, pid)
}

pub(crate) async fn check_ics_status(executor: &dyn CommandExecutor) -> (bool, u32) {
    match check_ics_status_native() {
        Ok(result) => result,
        Err(_) => match executor.run("sc", &["queryex", "SharedAccess"]).await {
            Ok(output) => parse_sc_queryex(&output.text()),
            Err(_) => (false, 0),
        },
    }
}

pub(crate) async fn stop_and_disable_shared_access() -> PlatformResult<()> {
    tokio::task::spawn_blocking(stop_and_disable_shared_access_blocking)
        .await
        .map_err(|error| PlatformError::message(format!("停止 SharedAccess 服务失败: {error}")))?
}

fn stop_and_disable_shared_access_blocking() -> PlatformResult<()> {
    let service = unsafe {
        let scm = OpenSCManagerW(ptr::null(), ptr::null(), SC_MANAGER_CONNECT);
        if scm.is_null() {
            return Err(PlatformError::message(format!(
                "打开服务控制管理器 (SCM) 失败: {}",
                GetLastError()
            )));
        }
        let name: Vec<u16> = "SharedAccess\0".encode_utf16().collect();
        let access = SERVICE_STOP | SERVICE_CHANGE_CONFIG | SERVICE_QUERY_STATUS;
        let service = OpenServiceW(scm, name.as_ptr(), access);
        CloseServiceHandle(scm);
        if service.is_null() {
            return Err(PlatformError::message(format!(
                "打开 SharedAccess 服务句柄失败: {}",
                GetLastError()
            )));
        }
        service
    };

    let mut status: SERVICE_STATUS_PROCESS = unsafe { std::mem::zeroed() };
    let mut needed = 0u32;
    let queried = unsafe {
        ChangeServiceConfigW(
            service,
            SERVICE_NO_CHANGE,
            SERVICE_DISABLED,
            SERVICE_NO_CHANGE,
            ptr::null(),
            ptr::null(),
            ptr::null_mut(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
        );
        QueryServiceStatusEx(
            service,
            SC_STATUS_PROCESS_INFO,
            &mut status as *mut _ as *mut u8,
            size_of::<SERVICE_STATUS_PROCESS>() as u32,
            &mut needed,
        )
    };
    if queried == 0 {
        let error = unsafe { GetLastError() };
        unsafe { CloseServiceHandle(service) };
        return Err(PlatformError::message(format!(
            "查询 SharedAccess 服务状态失败: {error}"
        )));
    }
    if status.dwCurrentState == SERVICE_STOPPED {
        unsafe { CloseServiceHandle(service) };
        return Ok(());
    }

    let mut stop_status: SERVICE_STATUS = unsafe { std::mem::zeroed() };
    let stopped = unsafe { ControlService(service, SERVICE_CONTROL_STOP, &mut stop_status) };
    if stopped == 0 {
        let error = unsafe { GetLastError() };
        unsafe { CloseServiceHandle(service) };
        return Err(PlatformError::message(format!(
            "向 SharedAccess 发送停止信号失败: {error}"
        )));
    }

    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(200));
        let mut poll: SERVICE_STATUS_PROCESS = unsafe { std::mem::zeroed() };
        let mut poll_needed = 0u32;
        let result = unsafe {
            QueryServiceStatusEx(
                service,
                SC_STATUS_PROCESS_INFO,
                &mut poll as *mut _ as *mut u8,
                size_of::<SERVICE_STATUS_PROCESS>() as u32,
                &mut poll_needed,
            )
        };
        if result != 0 && poll.dwCurrentState == SERVICE_STOPPED {
            unsafe { CloseServiceHandle(service) };
            return Ok(());
        }
    }

    unsafe { CloseServiceHandle(service) };
    Err(PlatformError::message(format!(
        "停止 SharedAccess 服务超时 (当前状态码: {})",
        stop_status.dwCurrentState
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sc_queryex_output_is_parsed() {
        let output = "SERVICE_NAME: SharedAccess\n        STATE              : 4  RUNNING\n        PID                : 1824\n";
        assert_eq!(parse_sc_queryex(output), (true, 1824));
        let stopped = "STATE : 1  STOPPED\nPID : 0\n";
        assert_eq!(parse_sc_queryex(stopped), (false, 0));
    }
}

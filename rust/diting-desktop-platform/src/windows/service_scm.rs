use std::ffi::c_void;
use std::ptr;

use diting_desktop_api::platform_types::{
    SERVICE_STATE_NOT_INSTALLED, SERVICE_STATE_RUNNING, SERVICE_STATE_START_PENDING,
    SERVICE_STATE_STOPPED, SERVICE_STATE_STOP_PENDING,
};
use windows_sys::Win32::Foundation::{
    GetLastError, ERROR_INSUFFICIENT_BUFFER, ERROR_SERVICE_ALREADY_RUNNING,
    ERROR_SERVICE_DOES_NOT_EXIST, ERROR_SERVICE_EXISTS, ERROR_SERVICE_NOT_ACTIVE,
};
use windows_sys::Win32::System::Services::{
    ChangeServiceConfig2W, CloseServiceHandle, ControlService, CreateServiceW, DeleteService,
    OpenSCManagerW, OpenServiceW, QueryServiceConfigW, QueryServiceStatus, StartServiceW,
    QUERY_SERVICE_CONFIGW, SC_HANDLE, SC_MANAGER_CONNECT, SC_MANAGER_CREATE_SERVICE,
    SERVICE_ALL_ACCESS, SERVICE_AUTO_START, SERVICE_CONFIG_DESCRIPTION, SERVICE_CONTROL_STOP,
    SERVICE_DESCRIPTIONW, SERVICE_ERROR_NORMAL, SERVICE_QUERY_CONFIG, SERVICE_QUERY_STATUS,
    SERVICE_RUNNING, SERVICE_START, SERVICE_START_PENDING, SERVICE_STATUS, SERVICE_STOP,
    SERVICE_STOPPED, SERVICE_STOP_PENDING, SERVICE_WIN32_OWN_PROCESS,
};

use crate::error::{PlatformError, PlatformResult};

use super::elevate::quote_argument;
use super::SERVICE_DISPLAY_NAME;

const SERVICE_DELETE_ACCESS: u32 = 0x0001_0000;

const SERVICE_DESCRIPTION: &str =
    "谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。";

fn last_error() -> u32 {
    unsafe { GetLastError() }
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

fn open_scm(access: u32) -> PlatformResult<SC_HANDLE> {
    let scm = unsafe { OpenSCManagerW(ptr::null(), ptr::null(), access) };
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

pub(super) fn query_start_type(service_name: &str) -> PlatformResult<u32> {
    let scm = open_scm(SC_MANAGER_CONNECT)?;
    let service = match open_service(scm, service_name, SERVICE_QUERY_CONFIG) {
        Ok(service) => service,
        Err(error) => {
            unsafe { CloseServiceHandle(scm) };
            return Err(error);
        }
    };

    let mut needed = 0u32;
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

pub(super) fn query_scm(service_name: &str) -> PlatformResult<(bool, bool, String)> {
    let scm = open_scm(SC_MANAGER_CONNECT)?;
    let name = wide(service_name);
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

fn service_command_line(exe_path: &str, args: &[String]) -> String {
    let mut line = format!("\"{exe_path}\" -run");
    for argument in args {
        line.push(' ');
        line.push_str(&quote_argument(argument));
    }
    line
}

pub(super) fn install_service_native(
    service_name: &str,
    exe_path: &str,
    args: &[String],
) -> PlatformResult<()> {
    let scm = open_scm(SC_MANAGER_CREATE_SERVICE)?;

    let name = wide(service_name);
    let display = wide(SERVICE_DISPLAY_NAME);
    let command_line = wide(&service_command_line(exe_path, args));
    let service = unsafe {
        CreateServiceW(
            scm,
            name.as_ptr(),
            display.as_ptr(),
            SERVICE_ALL_ACCESS,
            SERVICE_WIN32_OWN_PROCESS,
            SERVICE_AUTO_START,
            SERVICE_ERROR_NORMAL,
            command_line.as_ptr(),
            ptr::null(),
            ptr::null_mut(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
        )
    };
    if service.is_null() {
        let error = last_error();
        unsafe { CloseServiceHandle(scm) };
        if error == ERROR_SERVICE_EXISTS {
            return Ok(());
        }
        return Err(PlatformError::message(format!(
            "安装服务 [{service_name}] 失败: Windows 错误码 {error}"
        )));
    }

    let description = wide(SERVICE_DESCRIPTION);
    let mut info = SERVICE_DESCRIPTIONW {
        lpDescription: description.as_ptr() as *mut u16,
    };
    unsafe {
        ChangeServiceConfig2W(
            service,
            SERVICE_CONFIG_DESCRIPTION,
            &mut info as *mut SERVICE_DESCRIPTIONW as *const c_void,
        );
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
    }
    Ok(())
}

pub(super) fn start_service_native(service_name: &str) -> PlatformResult<()> {
    let scm = open_scm(SC_MANAGER_CONNECT)?;
    let service = match open_service(scm, service_name, SERVICE_START) {
        Ok(service) => service,
        Err(error) => {
            unsafe { CloseServiceHandle(scm) };
            return Err(error);
        }
    };
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

pub(super) fn stop_service_native(service_name: &str) -> PlatformResult<()> {
    let scm = open_scm(SC_MANAGER_CONNECT)?;
    let service = match open_service(scm, service_name, SERVICE_STOP | SERVICE_QUERY_STATUS) {
        Ok(service) => service,
        Err(error) => {
            unsafe { CloseServiceHandle(scm) };
            return Err(error);
        }
    };
    let mut status: SERVICE_STATUS = unsafe { std::mem::zeroed() };
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

pub(super) fn delete_service_native(service_name: &str) -> PlatformResult<()> {
    let scm = open_scm(SC_MANAGER_CONNECT)?;
    let name = wide(service_name);
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
    fn command_line_quotes_the_executable_and_keeps_flags() {
        let line = service_command_line(r"C:\Program Files\DITING\diting-service.exe", &[]);
        assert_eq!(line, r#""C:\Program Files\DITING\diting-service.exe" -run"#);
        let line = service_command_line(
            r"C:\DITING\diting-service.exe",
            &[
                String::from("-config"),
                String::from(r"D:\diting data\config.json"),
            ],
        );
        assert_eq!(
            line,
            r#""C:\DITING\diting-service.exe" -run -config "D:\diting data\config.json""#
        );
    }
}

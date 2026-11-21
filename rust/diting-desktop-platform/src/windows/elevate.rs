use std::mem::size_of;
use std::ptr;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use windows_sys::Win32::Foundation::{
    CloseHandle, GetLastError, ERROR_CANCELLED, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows_sys::Win32::System::Threading::{
    GetExitCodeProcess, TerminateProcess, WaitForSingleObject,
};
use windows_sys::Win32::UI::Shell::{ShellExecuteExW, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW};

use crate::error::{PlatformError, PlatformResult};
use crate::traits::PrivilegedExecutor;

pub const ERR_UAC_CANCELLED: &str = "用户取消了管理员权限授权";

const ELEVATED_TIMEOUT: Duration = Duration::from_secs(120);

pub struct WindowsPrivilegedExecutor;

impl WindowsPrivilegedExecutor {
    pub fn new() -> Self {
        Self
    }
}

impl Default for WindowsPrivilegedExecutor {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl PrivilegedExecutor for WindowsPrivilegedExecutor {
    async fn run_elevated(&self, exe: &str, args: &[String]) -> PlatformResult<()> {
        if crate::privilege::is_elevated() {
            let output = match tokio::time::timeout(
                ELEVATED_TIMEOUT,
                tokio::process::Command::new(exe)
                    .args(args)
                    .kill_on_drop(true)
                    .output(),
            )
            .await
            {
                Ok(output) => output?,
                Err(_) => return Err(PlatformError::message(format!("特权操作执行超时: {exe}"))),
            };
            if !output.status.success() {
                let mut combined = output.stdout;
                combined.extend_from_slice(&output.stderr);
                let text = String::from_utf8_lossy(&combined).trim().to_string();
                return Err(PlatformError::message(format!(
                    "特权操作执行失败: 退出代码 {} (输出: {text})",
                    output.status.code().unwrap_or(-1)
                )));
            }
            return Ok(());
        }

        let exe = exe.to_string();
        let parameters = compose_command_line(args);
        tokio::task::spawn_blocking(move || run_elevated_native(&exe, &parameters))
            .await
            .map_err(|error| PlatformError::message(format!("特权操作执行失败: {error}")))?
    }

    fn is_elevated(&self) -> bool {
        crate::privilege::is_elevated()
    }
}

fn run_elevated_native(exe: &str, parameters: &str) -> PlatformResult<()> {
    let verb = wide("runas");
    let file = wide(exe);
    let parameters = if parameters.is_empty() {
        None
    } else {
        Some(wide(parameters))
    };

    let mut info: SHELLEXECUTEINFOW = unsafe { std::mem::zeroed() };
    info.cbSize = size_of::<SHELLEXECUTEINFOW>() as u32;
    info.fMask = SEE_MASK_NOCLOSEPROCESS;
    info.lpVerb = verb.as_ptr();
    info.lpFile = file.as_ptr();
    info.lpParameters = parameters
        .as_ref()
        .map_or(ptr::null(), |value| value.as_ptr());
    info.nShow = 0;

    let success = unsafe { ShellExecuteExW(&mut info) };
    if success == 0 {
        let code = unsafe { GetLastError() };
        if code == ERROR_CANCELLED {
            return Err(PlatformError::message(ERR_UAC_CANCELLED));
        }
        return Err(PlatformError::message(format!(
            "特权操作执行失败: Windows 错误码 {code}"
        )));
    }

    if info.hProcess.is_null() {
        return Ok(());
    }

    let deadline = Instant::now() + ELEVATED_TIMEOUT;
    loop {
        let event = unsafe { WaitForSingleObject(info.hProcess, 100) };
        if event == WAIT_OBJECT_0 {
            break;
        }
        if event != WAIT_TIMEOUT {
            unsafe { CloseHandle(info.hProcess) };
            return Err(PlatformError::message(format!(
                "等待提权进程退出失败: Windows 错误码 {event}"
            )));
        }
        if Instant::now() >= deadline {
            let _ = unsafe { TerminateProcess(info.hProcess, 1) };
            unsafe { CloseHandle(info.hProcess) };
            return Err(PlatformError::message("特权操作执行超时，已终止提权进程"));
        }
    }

    let mut exit_code = 0u32;
    let read = unsafe { GetExitCodeProcess(info.hProcess, &mut exit_code) };
    unsafe { CloseHandle(info.hProcess) };
    if read != 0 && exit_code != 0 {
        return Err(PlatformError::message(format!(
            "特权操作执行失败 (退出代码: {exit_code})"
        )));
    }
    Ok(())
}

pub(crate) fn quote_argument(argument: &str) -> String {
    if !argument.is_empty() && !argument.contains([' ', '\t', '"']) {
        return argument.to_string();
    }

    let mut quoted = String::from("\"");
    let mut backslashes = 0usize;
    for character in argument.chars() {
        match character {
            '\\' => backslashes += 1,
            '"' => {
                quoted.push_str(&"\\".repeat(backslashes * 2 + 1));
                quoted.push('"');
                backslashes = 0;
            }
            _ => {
                if backslashes > 0 {
                    quoted.push_str(&"\\".repeat(backslashes));
                    backslashes = 0;
                }
                quoted.push(character);
            }
        }
    }
    quoted.push_str(&"\\".repeat(backslashes * 2));
    quoted.push('"');
    quoted
}

pub(crate) fn compose_command_line(args: &[String]) -> String {
    args.iter()
        .map(|argument| quote_argument(argument))
        .collect::<Vec<_>>()
        .join(" ")
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_arguments_remain_unquoted() {
        assert_eq!(quote_argument("install"), "install");
        assert_eq!(
            compose_command_line(&["-service".into(), "start".into()]),
            "-service start"
        );
    }

    #[test]
    fn paths_with_spaces_are_quoted() {
        assert_eq!(
            quote_argument(r"C:\Program Files\DITING\svc.exe"),
            "\"C:\\Program Files\\DITING\\svc.exe\""
        );
        assert_eq!(quote_argument(""), "\"\"");
    }

    #[test]
    fn embedded_quotes_are_backslash_escaped() {
        assert_eq!(quote_argument("a\"b"), "\"a\\\"b\"");
    }

    #[test]
    fn trailing_backslashes_before_quote_are_doubled() {
        assert_eq!(quote_argument("dir with space\\"), "\"dir with space\\\\\"");
    }
}

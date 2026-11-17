//! Per-user login auto-start via `HKCU\...\Run`.
//!
//! The desktop toggle means "start when this user signs in", so writes always target
//! `HKEY_CURRENT_USER`. Status reporting also scans `HKEY_USERS` because the service may run as
//! LocalSystem while the login item was registered in an interactive user's hive.

use std::ptr;

use diting_desktop_api::platform_types::{
    AutoStartStatus, AUTO_START_MECHANISM_LOGIN_ITEM, AUTO_START_MECHANISM_NONE,
};
use windows_sys::Win32::Foundation::ERROR_SUCCESS;
use windows_sys::Win32::System::Registry::{
    RegCloseKey, RegCreateKeyExW, RegDeleteValueW, RegEnumKeyExW, RegOpenKeyExW, RegQueryValueExW,
    RegSetValueExW, HKEY, HKEY_CURRENT_USER, HKEY_USERS, KEY_ENUMERATE_SUB_KEYS, KEY_QUERY_VALUE,
    KEY_SET_VALUE, REG_SZ,
};

use crate::error::{PlatformError, PlatformResult};
use crate::traits::AutoStartManager;

const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const RUN_VALUE_NAME: &str = "DitingDNS";
const ERROR_NO_MORE_ITEMS: u32 = 259;

pub struct WindowsAutoStart;

impl WindowsAutoStart {
    pub fn new() -> Self {
        Self
    }
}

impl Default for WindowsAutoStart {
    fn default() -> Self {
        Self::new()
    }
}

impl AutoStartManager for WindowsAutoStart {
    fn is_enabled(&self) -> bool {
        run_value_present(HKEY_CURRENT_USER, &[])
    }

    fn set_enabled(&self, enable: bool) -> PlatformResult<AutoStartStatus> {
        let key = create_run_key()?;
        if enable {
            let exe = std::env::current_exe()
                .map_err(|error| PlatformError::message(format!("获取执行路径失败: {error}")))?;
            let value = format!("\"{}\" --minimized", exe.display());
            // SAFETY: the key is valid and the value buffer lives through the call.
            let status = unsafe { write_string(key, RUN_VALUE_NAME, &value) };
            unsafe { RegCloseKey(key) };
            if status != ERROR_SUCCESS {
                return Err(PlatformError::message(format!(
                    "写入自启注册表失败: Windows 错误码 {status}"
                )));
            }
            return Ok(AutoStartStatus {
                enabled: true,
                mechanism: AUTO_START_MECHANISM_LOGIN_ITEM.to_string(),
                detail: "已加入 Windows 用户登录启动项，登录桌面后自动运行。".to_string(),
            });
        }

        // The value may already be absent; that is still success.
        unsafe {
            delete_value(key, RUN_VALUE_NAME);
            RegCloseKey(key);
        }
        Ok(AutoStartStatus {
            enabled: false,
            mechanism: AUTO_START_MECHANISM_NONE.to_string(),
            detail: "尚未配置任何开机自启托管机制。".to_string(),
        })
    }
}

/// Checks the login item across the current user and every loaded user hive. Used by the service
/// status aggregation, which cannot assume the service account owns the interactive hive.
pub(crate) fn login_item_enabled() -> bool {
    if run_value_present(HKEY_CURRENT_USER, &[]) {
        return true;
    }
    for sid in loaded_user_sids() {
        if run_value_present(HKEY_USERS, &[sid.as_str()]) {
            return true;
        }
    }
    false
}

fn run_path(subkeys: &[&str]) -> String {
    let mut path = RUN_KEY.to_string();
    for subkey in subkeys {
        path = format!("{subkey}\\{path}");
    }
    path
}

fn run_value_present(root: HKEY, subkeys: &[&str]) -> bool {
    let path = run_path(subkeys);
    let Some(key) = open_key(root, &path) else {
        return false;
    };
    // SAFETY: `key` is owned here and closed after the query.
    let value = unsafe {
        let value = read_string(key, RUN_VALUE_NAME);
        RegCloseKey(key);
        value
    };
    value.is_some()
}

fn loaded_user_sids() -> Vec<String> {
    let Some(users) = open_enum_key() else {
        return Vec::new();
    };
    let mut sids = Vec::new();
    let mut index = 0u32;

    loop {
        let mut name = [0u16; 256];
        let mut length = name.len() as u32;
        // SAFETY: buffered enumeration with the documented in/out length.
        let status = unsafe {
            RegEnumKeyExW(
                users,
                index,
                name.as_mut_ptr(),
                &mut length,
                ptr::null(),
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut(),
            )
        };
        if status == ERROR_NO_MORE_ITEMS {
            break;
        }
        if status != ERROR_SUCCESS {
            break;
        }
        sids.push(String::from_utf16_lossy(&name[..length as usize]));
        index += 1;
    }

    unsafe { RegCloseKey(users) };
    sids
}

fn open_key(root: HKEY, path: &str) -> Option<HKEY> {
    let path = wide(path);
    let mut key: HKEY = ptr::null_mut();
    // SAFETY: NUL-terminated path and a valid out-pointer.
    let status = unsafe { RegOpenKeyExW(root, path.as_ptr(), 0, KEY_QUERY_VALUE, &mut key) };
    if status == ERROR_SUCCESS {
        Some(key)
    } else {
        None
    }
}

fn open_enum_key() -> Option<HKEY> {
    let empty = wide("");
    let mut key: HKEY = ptr::null_mut();
    // SAFETY: `empty` is a NUL-terminated empty string; `key` is a valid out-pointer.
    let status = unsafe {
        RegOpenKeyExW(
            HKEY_USERS,
            empty.as_ptr(),
            0,
            KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS,
            &mut key,
        )
    };
    if status == ERROR_SUCCESS {
        Some(key)
    } else {
        None
    }
}

fn create_run_key() -> PlatformResult<HKEY> {
    let path = wide(RUN_KEY);
    let mut key: HKEY = ptr::null_mut();
    let mut disposition = 0u32;
    // SAFETY: all pointers are valid; null security attributes means the default ACL.
    let status = unsafe {
        RegCreateKeyExW(
            HKEY_CURRENT_USER,
            path.as_ptr(),
            0,
            ptr::null(),
            0,
            KEY_SET_VALUE,
            ptr::null(),
            &mut key,
            &mut disposition,
        )
    };
    if status == ERROR_SUCCESS {
        Ok(key)
    } else {
        Err(PlatformError::message(format!(
            "访问注册表失败: Windows 错误码 {status}"
        )))
    }
}

/// # Safety
/// `key` must be an open registry key.
unsafe fn read_string(key: HKEY, name: &str) -> Option<String> {
    let name = wide(name);
    let mut kind = 0u32;
    let mut size = 0u32;
    let status = RegQueryValueExW(
        key,
        name.as_ptr(),
        ptr::null(),
        &mut kind,
        ptr::null_mut(),
        &mut size,
    );
    if status != ERROR_SUCCESS || size == 0 || kind != REG_SZ {
        return None;
    }

    let mut data = vec![0u8; size as usize];
    let mut actual = size;
    let status = RegQueryValueExW(
        key,
        name.as_ptr(),
        ptr::null(),
        &mut kind,
        data.as_mut_ptr(),
        &mut actual,
    );
    if status != ERROR_SUCCESS {
        return None;
    }
    data.truncate(actual as usize);
    let mut units: Vec<u16> = data
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u16::from_le_bytes(*pair))
        .collect();
    while units.last() == Some(&0) {
        units.pop();
    }
    Some(String::from_utf16_lossy(&units))
}

/// # Safety
/// `key` must be an open key with `KEY_SET_VALUE`.
unsafe fn write_string(key: HKEY, name: &str, value: &str) -> u32 {
    let name = wide(name);
    let data: Vec<u16> = value.encode_utf16().chain(std::iter::once(0)).collect();
    RegSetValueExW(
        key,
        name.as_ptr(),
        0,
        REG_SZ,
        data.as_ptr() as *const u8,
        (data.len() * 2) as u32,
    )
}

/// # Safety
/// `key` must be an open key with `KEY_SET_VALUE`.
unsafe fn delete_value(key: HKEY, name: &str) {
    let name = wide(name);
    RegDeleteValueW(key, name.as_ptr());
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_nesting_matches_go() {
        assert_eq!(
            run_path(&[]),
            r"Software\Microsoft\Windows\CurrentVersion\Run"
        );
        assert_eq!(
            run_path(&["S-1-5-21"]),
            r"S-1-5-21\Software\Microsoft\Windows\CurrentVersion\Run"
        );
        assert_eq!(
            run_path(&["a", "b"]),
            r"b\a\Software\Microsoft\Windows\CurrentVersion\Run"
        );
    }
}

use std::net::IpAddr;
use std::ptr;

use windows_sys::Win32::Foundation::ERROR_SUCCESS;
use windows_sys::Win32::System::Registry::{
    RegCloseKey, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_LOCAL_MACHINE, KEY_QUERY_VALUE,
    REG_DWORD, REG_SZ,
};

use crate::netutil::is_loopback_or_local_ip;

pub(crate) fn normalize_guid(guid: &str) -> String {
    let clean = guid.trim().trim_matches(|ch| ch == '{' || ch == '}');
    if clean.is_empty() {
        String::new()
    } else {
        format!("{{{clean}}}")
    }
}

pub(crate) fn is_loopback_literal(text: &str) -> bool {
    let trimmed = text.trim();
    if let Ok(address) = trimmed.parse::<IpAddr>() {
        return address.is_loopback() || address.is_unspecified();
    }
    is_loopback_or_local_ip(trimmed)
}

pub(crate) fn get_dhcp_config_from_registry(guid: &str) -> (bool, bool) {
    let mut v4_dhcp = true;
    let mut v6_dhcp = true;
    let guid = normalize_guid(guid);
    if guid.is_empty() {
        return (v4_dhcp, v6_dhcp);
    }

    let v4_path = format!(r"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{guid}");
    if let Some(key) = open_key(HKEY_LOCAL_MACHINE, &v4_path) {
        unsafe {
            let enable_dhcp = read_dword(key, "EnableDHCP");
            let name_server = read_string(key, "NameServer");
            RegCloseKey(key);

            let static_dns = parse_registry_name_server(&name_server.unwrap_or_default());
            match enable_dhcp {
                Some(0) => v4_dhcp = false,
                Some(_) => v4_dhcp = static_dns.is_empty(),
                None if !static_dns.is_empty() => v4_dhcp = false,
                None => {}
            }
        }
    }

    let v6_path = format!(r"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\{guid}");
    if let Some(key) = open_key(HKEY_LOCAL_MACHINE, &v6_path) {
        unsafe {
            let name_server = read_string(key, "NameServer");
            RegCloseKey(key);
            if !parse_registry_name_server(&name_server.unwrap_or_default()).is_empty() {
                v6_dhcp = false;
            }
        }
    }

    (v4_dhcp, v6_dhcp)
}

fn parse_registry_name_server(value: &str) -> Vec<String> {
    value
        .split([',', ' ', ';'])
        .map(str::trim)
        .filter(|item| !item.is_empty() && !is_loopback_literal(item))
        .map(str::to_string)
        .collect()
}

pub(crate) fn check_registry_contains_loopback(guid: &str) -> bool {
    let guid = normalize_guid(guid);
    if guid.is_empty() {
        return false;
    }

    for service in ["Tcpip", "Tcpip6"] {
        let path =
            format!(r"SYSTEM\CurrentControlSet\Services\{service}\Parameters\Interfaces\{guid}");
        let Some(key) = open_key(HKEY_LOCAL_MACHINE, &path) else {
            continue;
        };
        let value = unsafe {
            let value = read_string(key, "NameServer");
            RegCloseKey(key);
            value
        };
        if value
            .unwrap_or_default()
            .split([',', ' ', ';'])
            .any(is_loopback_literal)
        {
            return true;
        }
    }

    false
}

pub(crate) fn read_machine_string(path: &str, value_name: &str) -> Option<String> {
    let key = open_key(HKEY_LOCAL_MACHINE, path)?;
    unsafe {
        let value = read_string(key, value_name);
        RegCloseKey(key);
        value
    }
}

fn open_key(root: HKEY, path: &str) -> Option<HKEY> {
    let path = wide(path);
    let mut key: HKEY = ptr::null_mut();
    let status = unsafe { RegOpenKeyExW(root, path.as_ptr(), 0, KEY_QUERY_VALUE, &mut key) };
    if status == ERROR_SUCCESS {
        Some(key)
    } else {
        None
    }
}

unsafe fn read_dword(key: HKEY, name: &str) -> Option<u32> {
    let name = wide(name);
    let mut kind = 0u32;
    let mut value: u32 = 0;
    let mut size = std::mem::size_of::<u32>() as u32;
    let status = RegQueryValueExW(
        key,
        name.as_ptr(),
        ptr::null(),
        &mut kind,
        &mut value as *mut u32 as *mut u8,
        &mut size,
    );
    if status == ERROR_SUCCESS && kind == REG_DWORD && size >= 4 {
        Some(value)
    } else {
        None
    }
}

unsafe fn read_string(key: HKEY, name: &str) -> Option<String> {
    let name = wide(name);
    let mut kind = 0u32;
    let mut size: u32 = 0;
    let status = RegQueryValueExW(
        key,
        name.as_ptr(),
        ptr::null(),
        &mut kind,
        ptr::null_mut(),
        &mut size,
    );
    if status != ERROR_SUCCESS || size == 0 {
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
    if status != ERROR_SUCCESS || kind != REG_SZ {
        return None;
    }
    data.truncate(actual as usize);
    Some(decode_utf16_bytes(&data))
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

fn decode_utf16_bytes(bytes: &[u8]) -> String {
    let mut units: Vec<u16> = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u16::from_le_bytes(*pair))
        .collect();
    while units.last() == Some(&0) {
        units.pop();
    }
    String::from_utf16_lossy(&units)
}

pub(crate) fn expand_env(text: &str) -> String {
    let mut result = String::with_capacity(text.len());
    let chars: Vec<char> = text.chars().collect();
    let mut index = 0;
    while index < chars.len() {
        if chars[index] == '%' {
            if let Some(end) = chars[index + 1..].iter().position(|ch| *ch == '%') {
                let name: String = chars[index + 1..index + 1 + end].iter().collect();
                if let Some(value) = std::env::var_os(&name) {
                    result.push_str(&value.to_string_lossy());
                }
                index += end + 2;
                continue;
            }
        }
        if chars[index] == '$' {
            let (name, consumed) = if chars.get(index + 1) == Some(&'{') {
                let end = chars[index + 2..]
                    .iter()
                    .position(|ch| *ch == '}')
                    .map(|offset| index + 2 + offset);
                match end {
                    Some(end) => (
                        chars[index + 2..end].iter().collect::<String>(),
                        end - index + 1,
                    ),
                    None => (String::new(), 0),
                }
            } else {
                let end = chars[index + 1..]
                    .iter()
                    .position(|ch| !ch.is_ascii_alphanumeric() && *ch != '_')
                    .map(|offset| index + 1 + offset)
                    .unwrap_or(chars.len());
                (
                    chars[index + 1..end].iter().collect::<String>(),
                    end - index,
                )
            };
            if consumed > 0 && !name.is_empty() {
                if let Some(value) = std::env::var_os(&name) {
                    result.push_str(&value.to_string_lossy());
                    index += consumed;
                    continue;
                }
            }
        }
        result.push(chars[index]);
        index += 1;
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guid_normalization_matches_registry_form() {
        assert_eq!(normalize_guid(" a-b "), "{a-b}");
        assert_eq!(normalize_guid("{a-b}"), "{a-b}");
        assert_eq!(normalize_guid("  "), "");
    }

    #[test]
    fn name_server_split_filters_loopback_and_empty() {
        assert_eq!(
            parse_registry_name_server("8.8.8.8, 1.1.1.1;127.0.0.1 ::1"),
            vec!["8.8.8.8".to_string(), "1.1.1.1".to_string()]
        );
        assert!(parse_registry_name_server("").is_empty());
    }

    #[test]
    fn bare_loopback_ipv6_is_recognized() {
        assert!(is_loopback_literal("::1"));
        assert!(is_loopback_literal("127.0.0.1"));
        assert!(is_loopback_literal("[::1]:53"));
        assert!(!is_loopback_literal("2606:4700:4700::1111"));
    }

    #[test]
    fn env_expansion_handles_percent_and_dollar_forms() {
        std::env::set_var("DITING_TEST_VAR", "value");
        assert_eq!(expand_env("%DITING_TEST_VAR%\\x"), "value\\x");
        assert_eq!(expand_env("$DITING_TEST_VAR/x"), "value/x");
        assert_eq!(expand_env("${DITING_TEST_VAR}x"), "valuex");
        assert_eq!(expand_env("plain"), "plain");
    }

    #[test]
    fn utf16_bytes_drop_trailing_nul() {
        let encoded: Vec<u8> = "abc\0".encode_utf16().flat_map(u16::to_le_bytes).collect();
        assert_eq!(decode_utf16_bytes(&encoded), "abc");
    }
}

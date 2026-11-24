use std::env;
use std::path::{Path, PathBuf};

pub const ENV_DATA_DIR: &str = "DITING_DATA_DIR";
pub const ENV_FORCE_OPENWRT: &str = "DITING_FORCE_OPENWRT";
pub const OPENWRT_RELEASE_PATH: &str = "/etc/openwrt_release";

pub const DEFAULT_CONFIG_FILE_NAME: &str = "config.json";
pub const DEFAULT_DB_FILE_NAME: &str = "diting.db";
pub const DEFAULT_QUERY_LOG_DB_FILE_NAME: &str = "querylog.db";
pub const DEFAULT_STATE_FILE_NAME: &str = "dns_state.json";
pub const DEFAULT_FILTER_DIR_NAME: &str = "filters";
pub const DEFAULT_QUERY_LOG_DIR_NAME: &str = "querylog";
pub const DEFAULT_CERT_DIR_NAME: &str = "certs";
pub const OPENWRT_PERSISTENT_DIR: &str = "/etc/diting";
pub const OPENWRT_VOLATILE_DIR: &str = "/tmp/diting";

pub fn is_openwrt() -> bool {
    if let Some(forced) = env::var_os(ENV_FORCE_OPENWRT) {
        let text = forced.to_string_lossy();
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            return matches!(trimmed, "1" | "true" | "TRUE" | "yes" | "YES");
        }
    }
    Path::new(OPENWRT_RELEASE_PATH).is_file()
}

pub fn openwrt_distro_name() -> Option<String> {
    let content = std::fs::read_to_string(OPENWRT_RELEASE_PATH).ok()?;
    parse_openwrt_release(&content)
}

pub fn parse_openwrt_release(content: &str) -> Option<String> {
    let mut distro_id = None;
    let mut release = None;
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(val) = trimmed.strip_prefix("DISTRIB_DESCRIPTION=") {
            let unquoted = unquote_shell_value(val);
            if !unquoted.is_empty() {
                return Some(unquoted);
            }
        } else if let Some(val) = trimmed.strip_prefix("DISTRIB_ID=") {
            let unquoted = unquote_shell_value(val);
            if !unquoted.is_empty() {
                distro_id = Some(unquoted);
            }
        } else if let Some(val) = trimmed.strip_prefix("DISTRIB_RELEASE=") {
            let unquoted = unquote_shell_value(val);
            if !unquoted.is_empty() {
                release = Some(unquoted);
            }
        }
    }
    match (distro_id, release) {
        (Some(id), Some(ver)) => Some(format!("{id} {ver}")),
        (Some(id), None) => Some(id),
        _ => None,
    }
}

fn unquote_shell_value(raw: &str) -> String {
    raw.trim()
        .trim_matches('\'')
        .trim_matches('"')
        .trim()
        .to_string()
}

pub fn default_data_dir() -> PathBuf {
    data_dir_from_env().unwrap_or_else(platform_data_dir)
}

pub fn default_config_dir() -> PathBuf {
    data_dir_from_env().unwrap_or_else(platform_config_dir)
}

pub fn default_volatile_dir() -> PathBuf {
    if let Some(custom) = data_dir_from_env() {
        return custom;
    }
    if is_openwrt() {
        return PathBuf::from(OPENWRT_VOLATILE_DIR);
    }
    platform_data_dir()
}

pub fn default_config_path() -> PathBuf {
    default_config_dir().join(DEFAULT_CONFIG_FILE_NAME)
}

pub fn default_db_path() -> PathBuf {
    default_data_dir().join(DEFAULT_DB_FILE_NAME)
}

pub fn default_state_file_path() -> PathBuf {
    default_data_dir().join(DEFAULT_STATE_FILE_NAME)
}

pub fn default_filter_dir() -> PathBuf {
    default_data_dir().join(DEFAULT_FILTER_DIR_NAME)
}

pub fn default_query_log_dir() -> PathBuf {
    if let Some(custom) = data_dir_from_env() {
        return custom.join(DEFAULT_QUERY_LOG_DIR_NAME);
    }
    if is_openwrt() {
        return PathBuf::from(OPENWRT_VOLATILE_DIR);
    }
    default_data_dir().join(DEFAULT_QUERY_LOG_DIR_NAME)
}

pub fn default_cert_dir() -> PathBuf {
    default_data_dir().join(DEFAULT_CERT_DIR_NAME)
}

fn data_dir_from_env() -> Option<PathBuf> {
    let custom = env::var_os(ENV_DATA_DIR)?;
    if custom.is_empty() {
        return None;
    }
    Some(PathBuf::from(custom).join("DITING"))
}

#[cfg(windows)]
fn platform_data_dir() -> PathBuf {
    windows_program_data_dir()
}

#[cfg(windows)]
fn platform_config_dir() -> PathBuf {
    windows_program_data_dir()
}

#[cfg(windows)]
fn windows_program_data_dir() -> PathBuf {
    let program_data = env::var_os("ProgramData")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
    program_data.join("DITING")
}

#[cfg(unix)]
fn platform_data_dir() -> PathBuf {
    if is_openwrt() && is_root() {
        return PathBuf::from(OPENWRT_PERSISTENT_DIR);
    }
    if is_root() {
        return PathBuf::from("/var/lib/diting");
    }
    home_diting_dir().unwrap_or_else(|| {
        if is_openwrt() {
            PathBuf::from(OPENWRT_PERSISTENT_DIR)
        } else {
            PathBuf::from("/var/lib/diting")
        }
    })
}

#[cfg(unix)]
fn platform_config_dir() -> PathBuf {
    if is_root() {
        return PathBuf::from("/etc/diting");
    }
    home_diting_dir().unwrap_or_else(|| PathBuf::from("/etc/diting"))
}

#[cfg(unix)]
fn home_diting_dir() -> Option<PathBuf> {
    env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(|home| PathBuf::from(home).join(".diting"))
}

#[cfg(unix)]
fn is_root() -> bool {
    #[cfg(target_os = "linux")]
    {
        let Ok(status) = std::fs::read_to_string("/proc/self/status") else {
            return false;
        };
        status.lines().any(|line| {
            line.strip_prefix("Uid:")
                .and_then(|rest| rest.split_whitespace().next())
                .and_then(|uid| uid.parse::<u32>().ok())
                == Some(0)
        })
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_are_composed_from_their_roots() {
        let data = default_data_dir();
        assert_eq!(default_filter_dir(), data.join(DEFAULT_FILTER_DIR_NAME));
        if !is_openwrt() {
            assert_eq!(
                default_query_log_dir(),
                data.join(DEFAULT_QUERY_LOG_DIR_NAME)
            );
        }
        assert_eq!(default_cert_dir(), data.join(DEFAULT_CERT_DIR_NAME));
        assert_eq!(
            default_state_file_path(),
            data.join(DEFAULT_STATE_FILE_NAME)
        );
        assert_eq!(default_db_path(), data.join(DEFAULT_DB_FILE_NAME));
        assert_eq!(
            default_config_path(),
            default_config_dir().join(DEFAULT_CONFIG_FILE_NAME)
        );
    }

    #[test]
    fn parses_openwrt_release_descriptions() {
        let sample = "DISTRIB_ID='OpenWrt'\nDISTRIB_RELEASE='23.05.5'\nDISTRIB_DESCRIPTION='OpenWrt 23.05.5 r24106-10cc5fcd00'\n";
        assert_eq!(
            parse_openwrt_release(sample).as_deref(),
            Some("OpenWrt 23.05.5 r24106-10cc5fcd00")
        );
        let fallback = "DISTRIB_ID=\"ImmortalWrt\"\nDISTRIB_RELEASE=\"24.10.0\"\n";
        assert_eq!(
            parse_openwrt_release(fallback).as_deref(),
            Some("ImmortalWrt 24.10.0")
        );
    }
}

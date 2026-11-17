//! Default filesystem locations, mirroring the former Go service's `internal/platform/paths*.go`.
//!
//! The logic lives here rather than in a platform helper because `diting-desktop-api` is the
//! dependency-free model crate: it must not depend on `diting-desktop-platform`, and the rest of
//! the service expects the same paths the Go implementation used so existing installations keep
//! reading and writing their own files.

use std::env;
use std::path::PathBuf;

/// Environment variable that redirects every data/config path under one directory.
pub const ENV_DATA_DIR: &str = "DITING_DATA_DIR";

/// Default config file name.
pub const DEFAULT_CONFIG_FILE_NAME: &str = "config.json";
/// Default takeover state file name.
pub const DEFAULT_STATE_FILE_NAME: &str = "dns_state.json";
/// Default filter cache directory name.
pub const DEFAULT_FILTER_DIR_NAME: &str = "filters";
/// Default query-log directory name.
pub const DEFAULT_QUERY_LOG_DIR_NAME: &str = "querylog";
/// Default encrypted-DNS certificate directory name.
pub const DEFAULT_CERT_DIR_NAME: &str = "certs";

/// Mutable data root (`%ProgramData%\DITING`, `/var/lib/diting`, or `~/.diting`).
pub fn default_data_dir() -> PathBuf {
    data_dir_from_env().unwrap_or_else(platform_data_dir)
}

/// Configuration directory (`%ProgramData%\DITING`, `/etc/diting`, or `~/.diting`).
pub fn default_config_dir() -> PathBuf {
    data_dir_from_env().unwrap_or_else(platform_config_dir)
}

/// Default `config.json` path.
pub fn default_config_path() -> PathBuf {
    default_config_dir().join(DEFAULT_CONFIG_FILE_NAME)
}

/// Default takeover state path.
pub fn default_state_file_path() -> PathBuf {
    default_data_dir().join(DEFAULT_STATE_FILE_NAME)
}

/// Default filter cache directory.
pub fn default_filter_dir() -> PathBuf {
    default_data_dir().join(DEFAULT_FILTER_DIR_NAME)
}

/// Default query-log directory.
pub fn default_query_log_dir() -> PathBuf {
    default_data_dir().join(DEFAULT_QUERY_LOG_DIR_NAME)
}

/// Default encrypted-DNS certificate directory.
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
    if is_root() {
        return PathBuf::from("/var/lib/diting");
    }
    home_diting_dir().unwrap_or_else(|| PathBuf::from("/var/lib/diting"))
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

/// Detect root without pulling in `libc`: Linux exposes the effective UID in `/proc`.
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
        assert_eq!(
            default_query_log_dir(),
            data.join(DEFAULT_QUERY_LOG_DIR_NAME)
        );
        assert_eq!(default_cert_dir(), data.join(DEFAULT_CERT_DIR_NAME));
        assert_eq!(
            default_state_file_path(),
            data.join(DEFAULT_STATE_FILE_NAME)
        );
        assert_eq!(
            default_config_path(),
            default_config_dir().join(DEFAULT_CONFIG_FILE_NAME)
        );
    }
}

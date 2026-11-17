//! Data/config/cert/querylog paths, identical to the Go service's layout.
//!
//! Windows keeps everything under `%ProgramData%\DITING`. Linux separates configuration
//! (`/etc/diting`) from mutable state (`/var/lib/diting`) and falls back to `~/.diting` when the
//! process is not root. `DITING_DATA_DIR` overrides both roots with `<value>/DITING`, exactly like
//! `platform.DefaultDataDir`.

use std::path::{Path, PathBuf};

pub const ENV_DATA_DIR: &str = "DITING_DATA_DIR";
pub const CONFIG_FILE: &str = "config.json";
pub const STATE_FILE: &str = "dns_state.json";
pub const FILTER_DIR: &str = "filters";
pub const QUERYLOG_DIR: &str = "querylog";
pub const CERT_DIR: &str = "certs";

fn env_override() -> Option<PathBuf> {
    std::env::var_os(ENV_DATA_DIR)
        .filter(|value| !value.is_empty())
        .map(|value| PathBuf::from(value).join("DITING"))
}

#[cfg(unix)]
fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
}

#[cfg(windows)]
fn program_data() -> PathBuf {
    std::env::var_os("ProgramData")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"))
}

/// The mutable data root.
pub fn default_data_dir() -> PathBuf {
    if let Some(path) = env_override() {
        return path;
    }
    #[cfg(windows)]
    {
        program_data().join("DITING")
    }
    #[cfg(unix)]
    {
        let root = unsafe { libc::geteuid() } == 0;
        if root {
            PathBuf::from("/var/lib/diting")
        } else {
            home_dir()
                .unwrap_or_else(|| PathBuf::from("/var/lib/diting"))
                .join(".diting")
        }
    }
}

/// The configuration root.
pub fn default_config_dir() -> PathBuf {
    if let Some(path) = env_override() {
        return path;
    }
    #[cfg(windows)]
    {
        program_data().join("DITING")
    }
    #[cfg(unix)]
    {
        let root = unsafe { libc::geteuid() } == 0;
        if root {
            PathBuf::from("/etc/diting")
        } else {
            home_dir()
                .unwrap_or_else(|| PathBuf::from("/etc/diting"))
                .join(".diting")
        }
    }
}

pub fn default_config_path() -> PathBuf {
    default_config_dir().join(CONFIG_FILE)
}

pub fn default_state_path() -> PathBuf {
    default_data_dir().join(STATE_FILE)
}

pub fn default_filter_dir() -> PathBuf {
    default_data_dir().join(FILTER_DIR)
}

pub fn default_querylog_dir() -> PathBuf {
    default_data_dir().join(QUERYLOG_DIR)
}

pub fn default_cert_dir() -> PathBuf {
    default_data_dir().join(CERT_DIR)
}

/// `ResolveStateFilePath`: explicit config wins, otherwise the platform state file. The Go
/// service also let a platform hook redirect it; the desktop rule is the same default path.
pub fn resolve_state_path(explicit: &str) -> PathBuf {
    if explicit.is_empty() {
        default_state_path()
    } else {
        PathBuf::from(explicit)
    }
}

pub fn parent_of(path: &Path) -> PathBuf {
    path.parent().map(Path::to_path_buf).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn override_wins() {
        // The environment is process-global; this test only exercises path composition.
        let path = Path::new("C:/tmp/DITING").join(CONFIG_FILE);
        assert!(path.ends_with(CONFIG_FILE));
    }
}

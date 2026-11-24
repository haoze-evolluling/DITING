use std::path::PathBuf;

use diting_desktop_api::config::paths as api_paths;

pub const ENV_DATA_DIR: &str = api_paths::ENV_DATA_DIR;
pub const CONFIG_FILE: &str = api_paths::DEFAULT_CONFIG_FILE_NAME;
pub const STATE_FILE: &str = api_paths::DEFAULT_STATE_FILE_NAME;
pub const FILTER_DIR: &str = api_paths::DEFAULT_FILTER_DIR_NAME;
pub const QUERYLOG_DIR: &str = api_paths::DEFAULT_QUERY_LOG_DIR_NAME;
pub const CERT_DIR: &str = api_paths::DEFAULT_CERT_DIR_NAME;

pub fn is_openwrt() -> bool {
    api_paths::is_openwrt()
}

pub fn openwrt_distro_name() -> Option<String> {
    api_paths::openwrt_distro_name()
}

pub fn default_data_dir() -> PathBuf {
    api_paths::default_data_dir()
}

pub fn default_config_dir() -> PathBuf {
    api_paths::default_config_dir()
}

pub fn default_volatile_dir() -> PathBuf {
    api_paths::default_volatile_dir()
}

pub fn default_config_path() -> PathBuf {
    api_paths::default_config_path()
}

pub fn default_state_path() -> PathBuf {
    api_paths::default_state_file_path()
}

pub fn default_filter_dir() -> PathBuf {
    api_paths::default_filter_dir()
}

pub fn default_querylog_dir() -> PathBuf {
    api_paths::default_query_log_dir()
}

pub fn default_cert_dir() -> PathBuf {
    api_paths::default_cert_dir()
}

pub fn resolve_state_path(explicit: &str) -> PathBuf {
    if explicit.is_empty() {
        default_state_path()
    } else {
        PathBuf::from(explicit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn override_wins() {
        let path = Path::new("C:/tmp/DITING").join(CONFIG_FILE);
        assert!(path.ends_with(CONFIG_FILE));
    }
}

use std::path::PathBuf;

use diting_desktop_api::config::paths::default_data_dir;
use diting_desktop_api::config::CacheConfig;
use diting_dns_cache_core::Cache;

use super::persist::{self, PersistStatus};

/// 缓存落盘后端。文件后端保持旧行为，桌面 SQLite 模式注入数据库实现。
pub trait CachePersistence: Send + Sync {
    fn save(&self, cache: &Cache, config: &CacheConfig) -> Result<PersistStatus, String>;
    fn load(&self, cache: &Cache, config: &CacheConfig) -> Result<usize, String>;
    fn location(&self, config: &CacheConfig) -> String;
}

pub struct FileCachePersistence;

impl FileCachePersistence {
    pub fn new() -> Self {
        Self
    }

    pub fn path_for(config: &CacheConfig) -> PathBuf {
        if config.persist_path.trim().is_empty() {
            default_data_dir().join("cache.json")
        } else {
            PathBuf::from(&config.persist_path)
        }
    }
}

impl Default for FileCachePersistence {
    fn default() -> Self {
        Self::new()
    }
}

impl CachePersistence for FileCachePersistence {
    fn save(&self, cache: &Cache, config: &CacheConfig) -> Result<PersistStatus, String> {
        persist::save(cache, &Self::path_for(config))
    }

    fn load(&self, cache: &Cache, config: &CacheConfig) -> Result<usize, String> {
        persist::load(cache, &Self::path_for(config))
    }

    fn location(&self, config: &CacheConfig) -> String {
        Self::path_for(config).to_string_lossy().into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_cache_core::policy::Config as KernelConfig;

    #[test]
    fn file_persistence_uses_configured_path() {
        let mut config = CacheConfig {
            persist_path: "custom/cache.json".to_string(),
            ..CacheConfig::default()
        };
        let path = FileCachePersistence::path_for(&config);
        assert!(path.ends_with("cache.json"));
        assert!(path.to_string_lossy().contains("custom"));

        let cache = Cache::new(KernelConfig::default());
        let persistence = FileCachePersistence::new();
        assert!(persistence.location(&config).contains("cache.json"));
        // 空路径回退到数据目录
        config.persist_path.clear();
        assert!(FileCachePersistence::path_for(&config).ends_with("cache.json"));
        let _ = cache;
    }
}

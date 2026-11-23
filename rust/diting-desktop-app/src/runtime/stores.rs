use std::path::PathBuf;
use std::sync::Arc;

use diting_desktop_api::config::{Config, ConfigStore, FileConfigStore};
use diting_desktop_core::cache::{CachePersistence, FileCachePersistence};
use diting_desktop_core::filter::{FileListCache, ListCache};
use diting_desktop_core::querylog::QueryLogStorage;

/// 运行时注入的持久化后端。默认构造函数保持文件行为，桌面服务可替换为 SQLite。
pub struct RuntimeStores {
    pub backend: &'static str,
    pub config: Arc<dyn ConfigStore>,
    pub querylog: Option<Arc<dyn QueryLogStorage>>,
    pub list_cache: Arc<dyn ListCache>,
    pub cache: Arc<dyn CachePersistence>,
}

impl RuntimeStores {
    pub fn file(config_path: PathBuf, config: &Config) -> Self {
        Self {
            backend: "file",
            config: Arc::new(FileConfigStore::new(config_path)),
            querylog: None,
            list_cache: Arc::new(FileListCache::new(&config.filter.data_dir)),
            cache: Arc::new(FileCachePersistence::new()),
        }
    }
}

use std::io;
use std::path::PathBuf;
use std::sync::RwLock;

use super::fetch;

/// 规则正文的存储后端。文件后端保持旧行为，桌面 SQLite 模式注入数据库实现。
pub trait ListCache: Send + Sync {
    fn read(&self, id: &str) -> Option<Vec<u8>>;
    fn write(&self, id: &str, data: &[u8]) -> io::Result<()>;
    fn remove(&self, id: &str);

    /// 文件后端在 `filter.dataDir` 变化时重新绑定；数据库后端忽略。
    fn set_data_dir(&self, _data_dir: &str) {}
}

pub struct FileListCache {
    data_dir: RwLock<PathBuf>,
}

impl FileListCache {
    pub fn new(data_dir: impl Into<PathBuf>) -> Self {
        Self {
            data_dir: RwLock::new(data_dir.into()),
        }
    }

    fn dir(&self) -> PathBuf {
        self.data_dir
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }
}

impl ListCache for FileListCache {
    fn read(&self, id: &str) -> Option<Vec<u8>> {
        let dir = self.dir();
        fetch::read_cache(dir.to_string_lossy().as_ref(), id)
    }

    fn write(&self, id: &str, data: &[u8]) -> io::Result<()> {
        let dir = self.dir();
        fetch::write_cache_atomic(dir.to_string_lossy().as_ref(), id, data)
    }

    fn remove(&self, id: &str) {
        let dir = self.dir();
        fetch::remove_cache(dir.to_string_lossy().as_ref(), id);
    }

    fn set_data_dir(&self, data_dir: &str) {
        *self
            .data_dir
            .write()
            .unwrap_or_else(|error| error.into_inner()) = PathBuf::from(data_dir);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_cache_round_trip_and_rebind() {
        let dir = std::env::temp_dir().join(format!(
            "diting-list-cache-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|value| value.as_nanos())
                .unwrap_or(0)
        ));
        let cache = FileListCache::new(&dir);
        cache.write("list-a", b"||a.com^\n").unwrap();
        assert_eq!(cache.read("list-a").as_deref(), Some(&b"||a.com^\n"[..]));
        cache.remove("list-a");
        assert!(cache.read("list-a").is_none());
        let _ = std::fs::remove_dir_all(dir);
    }
}

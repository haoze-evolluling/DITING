//! `dns_state.json`, the crash-recovery snapshot of the pre-takeover adapter DNS.
//!
//! The write is deliberate about ordering: temporary file, fsync-free atomic rename, and on
//! Windows a best-effort delete first (some filesystems refuse to replace a locked target). A
//! half-written state file would make the service restore the wrong DNS after a crash, so the
//! reader treats unparsable content as an error rather than silently starting fresh.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use diting_desktop_api::platform_types::TakeoverState;

use crate::error::{PlatformError, PlatformResult};
use crate::paths;
use crate::traits::StateStore;

pub struct FileStateStore {
    file_path: PathBuf,
    write_lock: Mutex<()>,
}

impl FileStateStore {
    /// Uses the platform default state file when `path` is empty.
    pub fn new(path: impl AsRef<Path>) -> Self {
        let path = path.as_ref();
        let file_path = if path.as_os_str().is_empty() {
            paths::default_state_path()
        } else {
            path.to_path_buf()
        };
        Self {
            file_path,
            write_lock: Mutex::new(()),
        }
    }

    pub fn with_default_path() -> Self {
        Self::new("")
    }

    pub fn timestamp_now() -> String {
        chrono::Local::now().to_rfc3339_opts(chrono::SecondsFormat::Nanos, true)
    }
}

impl StateStore for FileStateStore {
    fn save(&self, state: &TakeoverState) -> PlatformResult<()> {
        let _guard = self
            .write_lock
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(parent) = self.file_path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|error| {
                    PlatformError::message(format!("创建状态目录失败: {error}"))
                })?;
            }
        }
        let data = serde_json::to_vec_pretty(state)
            .map_err(|error| PlatformError::message(format!("序列化接管状态失败: {error}")))?;
        let tmp = self.file_path.with_extension("json.tmp");
        std::fs::write(&tmp, data)
            .map_err(|error| PlatformError::message(format!("写入临时状态文件失败: {error}")))?;
        let _ = std::fs::remove_file(&self.file_path);
        if let Err(error) = std::fs::rename(&tmp, &self.file_path) {
            let _ = std::fs::remove_file(&tmp);
            return Err(PlatformError::message(format!(
                "重命名替换状态文件失败: {error}"
            )));
        }
        Ok(())
    }

    fn load(&self) -> PlatformResult<Option<TakeoverState>> {
        let data = match std::fs::read(&self.file_path) {
            Ok(data) => data,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(PlatformError::message(format!("读取状态文件失败: {error}"))),
        };
        let state = serde_json::from_slice(&data)
            .map_err(|error| PlatformError::message(format!("反序列化状态文件失败: {error}")))?;
        Ok(Some(state))
    }

    fn clear(&self) -> PlatformResult<()> {
        match std::fs::remove_file(&self.file_path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(PlatformError::message(format!("清理状态文件失败: {error}"))),
        }
    }

    fn file_path(&self) -> &Path {
        &self.file_path
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::traits::Restorer;
    use async_trait::async_trait;
    use diting_desktop_api::platform_types::AdapterState;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct CountRestorer(AtomicUsize);

    #[async_trait]
    impl Restorer for CountRestorer {
        async fn restore_adapters(&self, _adapters: &[AdapterState]) -> PlatformResult<()> {
            self.0.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
    }

    fn temp_path(tag: &str) -> PathBuf {
        std::env::temp_dir()
            .join(format!("diting-state-{tag}-{}", std::process::id()))
            .join("dns_state.json")
    }

    #[test]
    fn save_load_clear() {
        let path = temp_path("roundtrip");
        let store = FileStateStore::new(&path);
        let state = TakeoverState {
            active: true,
            pid: 7,
            adapters: vec![AdapterState {
                id: "x".into(),
                ipv4_dns: vec!["1.1.1.1".into()],
                ..AdapterState::default()
            }],
            ..TakeoverState::default()
        };
        store.save(&state).unwrap();
        assert_eq!(store.load().unwrap().unwrap().adapters[0].id, "x");
        store.clear().unwrap();
        assert!(store.load().unwrap().is_none());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn missing_file_is_not_an_error() {
        let store = FileStateStore::new(temp_path("missing"));
        assert!(store.load().unwrap().is_none());
        store.clear().unwrap();
    }

    #[tokio::test]
    async fn self_heal_restores_leftover_takeover() {
        let path = temp_path("heal");
        let store = FileStateStore::new(&path);
        let state = TakeoverState {
            active: true,
            adapters: vec![AdapterState::default()],
            ..TakeoverState::default()
        };
        store.save(&state).unwrap();
        let restorer = CountRestorer(AtomicUsize::new(0));
        assert!(store.check_and_self_heal(Some(&restorer)).await.unwrap());
        assert_eq!(restorer.0.load(Ordering::SeqCst), 1);
        assert!(store.load().unwrap().is_none());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}

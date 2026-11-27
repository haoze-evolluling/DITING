use std::io;
use std::path::Path;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use diting_desktop_api::config::ConfigStore;
use diting_desktop_app::{settings, RuntimeStores};
use diting_desktop_core::querylog::{
    Config as QueryLogConfig, QueryLogStorage, Record, SearchQuery, SearchResult,
};
use diting_desktop_sqlite::{migrate, MigrationReport, SqliteConfigStore, SqliteDb};

use crate::config::{ListenConfig, ServerConfig};
use crate::paths::ServerPaths;

const META_CONFIG: &str = "server_config";
const META_CONFIG_UPDATED_AT: &str = "server_config_updated_at";
const META_LEGACY_MIGRATION: &str = "server_legacy_migration";
const FILE_NEWER_TOLERANCE_MS: i64 = 2_000;

/// 服务器模式结构化数据的持久化入口：`filesDir/server/server.db`。
///
/// 配置同时写入 `meta`（完整 `ServerConfig`，含 `listen`）与 `config_sections`
/// （桌面分节，便于按 schema 检查）；`config.json` 仅作为未运行时的兼容镜像。
pub struct ServerStorage {
    db: Arc<SqliteDb>,
}

impl ServerStorage {
    pub fn open(paths: &ServerPaths) -> Result<Self, String> {
        let db = SqliteDb::open(&paths.db_path)?;
        Ok(Self { db })
    }

    /// 第一次启动新版本时把旧的 JSONL / 规则 txt / cache.json / 配置导入数据库。
    pub fn migrate_legacy(&self, paths: &ServerPaths) -> Result<Option<MigrationReport>, String> {
        if self.db.meta_get(META_LEGACY_MIGRATION).as_deref() == Some("1") {
            return Ok(None);
        }
        let report = migrate(&self.db, &paths.config_path, &paths.data_dir, true)?;
        if report.errors.is_empty() {
            self.db.meta_set(META_LEGACY_MIGRATION, "1")?;
        }
        Ok(Some(report))
    }

    /// 选择配置来源并规范化后立即回写数据库与兼容镜像。
    ///
    /// `migrated` 是迁移前从 `config.json` 读到的内容。迁移会删掉旧文件，
    /// 因此这一份必须在迁移前取出并由调用方传入。
    pub fn load_config(
        &self,
        paths: &ServerPaths,
        port: u16,
        root: bool,
        bind_address: &str,
        migrated: Option<ServerConfig>,
    ) -> Result<ServerConfig, String> {
        let mut config = match migrated {
            Some(config) => config,
            None => self.load_preferred(paths),
        };
        config.normalize(paths, port, root, bind_address)?;
        self.save_config(paths, &config)?;
        Ok(config)
    }

    /// 离线维护时沿用已保存的监听身份。
    ///
    /// 服务未运行时的一次性请求不绑定端口，不能拿命令行默认值改写用户保存的
    /// `listen`（尤其是 Root / 53 端口），否则一次离线刷新就会把监听设置降级。
    pub fn load_config_preserving_listen(
        &self,
        paths: &ServerPaths,
    ) -> Result<ServerConfig, String> {
        // `save_config` 总是先写兼容镜像再写库，所以只要 `config.json` 存在，它就
        // 不会比数据库旧；离线请求直接以它为准，避免“停止时保存后 2 秒内再次刷新”
        // 读到数据库里的旧配置并把新改动覆盖回去。
        let mut config = std::fs::read(&paths.config_path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<ServerConfig>(&bytes).ok())
            .unwrap_or_else(|| self.load_preferred(paths));
        let listen = config.listen.clone();
        config.normalize(paths, listen.port, listen.root, &listen.bind_address)?;
        self.save_config(paths, &config)?;
        Ok(config)
    }

    /// 配置优先级：迁移前读取的 `config.json` > 数据库 `meta` > `config_sections` > 默认值。
    fn load_preferred(&self, paths: &ServerPaths) -> ServerConfig {
        let file_config = std::fs::read(&paths.config_path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<ServerConfig>(&bytes).ok());
        let meta_config = self
            .db
            .meta_get(META_CONFIG)
            .and_then(|raw| serde_json::from_str::<ServerConfig>(&raw).ok());
        if let Some(config) = file_config {
            let updated_at = self
                .db
                .meta_get(META_CONFIG_UPDATED_AT)
                .and_then(|raw| raw.parse::<i64>().ok())
                .unwrap_or(0);
            if meta_config.is_none()
                || file_mtime_ms(&paths.config_path) > updated_at + FILE_NEWER_TOLERANCE_MS
            {
                return config;
            }
        }
        meta_config.unwrap_or_else(|| self.config_from_sections())
    }

    fn config_from_sections(&self) -> ServerConfig {
        let desktop = SqliteConfigStore::new(Arc::clone(&self.db))
            .load()
            .unwrap_or_default();
        ServerConfig::from_desktop(ListenConfig::default(), desktop)
    }

    pub fn save_config(&self, paths: &ServerPaths, config: &ServerConfig) -> Result<(), String> {
        let doc = serde_json::to_string_pretty(config)
            .map_err(|error| format!("序列化服务器配置失败: {error}"))?;
        // 先写兼容镜像再写库：中途崩溃时下一次启动仍能从较新的 config.json 恢复。
        config.save(&paths.config_path)?;
        self.db.meta_set(META_CONFIG, &doc)?;
        self.db
            .meta_set(META_CONFIG_UPDATED_AT, &now_ms().to_string())?;
        SqliteConfigStore::new(Arc::clone(&self.db))
            .save(&config.desktop_config())
            .map_err(|error| format!("写入配置分节失败: {error}"))
    }

    pub fn runtime_stores(&self, config: &ServerConfig) -> RuntimeStores {
        let desktop = config.desktop_config();
        let querylog = settings::querylog_settings(&desktop.query_log);
        let mut stores = diting_desktop_sqlite::runtime_stores(Arc::clone(&self.db), &querylog);
        if let Some(inner) = stores.querylog.take() {
            stores.querylog = Some(Arc::new(MemoryCappedQueryLog(inner)));
        }
        stores
    }

    pub fn checkpoint(&self) -> Result<(), String> {
        self.db.checkpoint()
    }
}

/// 服务器界面的“内存条目上限”只约束内存环；数据库历史仅按保留天数清理。
struct MemoryCappedQueryLog(Arc<dyn QueryLogStorage>);

impl QueryLogStorage for MemoryCappedQueryLog {
    fn append(&self, record: Record) -> bool {
        self.0.append(record)
    }

    fn search(&self, query: &SearchQuery) -> Option<SearchResult> {
        self.0.search(query)
    }

    fn search_older(
        &self,
        query: &SearchQuery,
        mem_total: i64,
        mem_oldest: i64,
    ) -> (Vec<Record>, i64) {
        self.0.search_older(query, mem_total, mem_oldest)
    }

    fn recent(&self, since_ms: i64, limit: usize) -> Vec<Record> {
        self.0.recent(since_ms, limit)
    }

    fn configure(&self, config: &QueryLogConfig) {
        let mut next = config.clone();
        next.max_entries = 0;
        self.0.configure(&next);
    }

    fn clear(&self) -> io::Result<()> {
        self.0.clear()
    }

    fn close(&self) -> io::Result<()> {
        self.0.close()
    }

    fn is_persistent(&self) -> bool {
        self.0.is_persistent()
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

fn file_mtime_ms(path: &Path) -> i64 {
    std::fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(tag: &str) -> ServerPaths {
        let root = std::env::temp_dir().join(format!(
            "diting-server-storage-{tag}-{}-{}",
            std::process::id(),
            now_ms()
        ));
        let _ = std::fs::remove_dir_all(&root);
        ServerPaths::new(root)
    }

    #[test]
    fn offline_load_keeps_the_saved_listen_identity() {
        let paths = paths("offline-listen");
        paths.ensure_dirs().unwrap();
        let storage = ServerStorage::open(&paths).unwrap();
        let mut config = ServerConfig::default();
        config.normalize(&paths, 53, true, "127.0.0.1").unwrap();
        storage.save_config(&paths, &config).unwrap();

        let reloaded = storage.load_config_preserving_listen(&paths).unwrap();
        assert_eq!(reloaded.listen.port, 53);
        assert!(reloaded.listen.root);
        assert_eq!(reloaded.listen.bind_address, "127.0.0.1");

        // 服务停止时 Flutter 只写 config.json；离线请求必须以这份较新的镜像为准。
        let mut edited = config.clone();
        edited.filter.block_mode = "nxdomain".to_string();
        edited.save(&paths.config_path).unwrap();
        let reloaded = storage.load_config_preserving_listen(&paths).unwrap();
        assert_eq!(reloaded.filter.block_mode, "nxdomain");

        let _ = std::fs::remove_dir_all(&paths.data_dir);
    }

    #[test]
    fn saves_and_reloads_the_server_config() {
        let paths = paths("roundtrip");
        paths.ensure_dirs().unwrap();
        let storage = ServerStorage::open(&paths).unwrap();
        let mut config = ServerConfig::default();
        config.normalize(&paths, 1053, false, "0.0.0.0").unwrap();
        storage
            .load_config(&paths, 1053, false, "0.0.0.0", Some(config))
            .unwrap();

        let mut next = storage
            .load_config(&paths, 5353, true, "127.0.0.1", None)
            .unwrap();
        assert_eq!(next.listen.port, 5353);
        assert!(next.listen.root);
        next.upstream.mode = "parallel_race".to_string();
        storage.save_config(&paths, &next).unwrap();

        let reloaded = storage
            .load_config(&paths, 53, true, "0.0.0.0", None)
            .unwrap();
        assert_eq!(reloaded.upstream.mode, "parallel_race");
        assert!(paths.config_path.is_file());

        let _ = std::fs::remove_dir_all(&paths.data_dir);
    }
}

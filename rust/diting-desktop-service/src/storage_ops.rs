use std::path::{Path, PathBuf};
use std::sync::Arc;

use diting_desktop_api::config::paths as config_paths;
use diting_desktop_api::config::{store, Config, ConfigStore};
use diting_desktop_ipc::auth::hash_password;
use diting_desktop_ipc::session::SessionStore;
use diting_desktop_platform::paths;
use diting_desktop_platform::state::FileStateStore;
use diting_desktop_platform::traits::StateStore;

use crate::cli::Cli;

pub(crate) struct PreparedStorage {
    pub config: Config,
    pub stores: diting_desktop_app::RuntimeStores,
    pub background_dir: PathBuf,
    pub db: Option<Arc<diting_desktop_sqlite::SqliteDb>>,
}

fn is_json(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("json"))
}

pub(crate) fn db_path(cli: &Cli) -> PathBuf {
    if cli.config_path.is_empty() {
        return config_paths::default_db_path();
    }
    let path = PathBuf::from(&cli.config_path);
    if is_json(&path) {
        path.parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .map(|parent| parent.join("diting.db"))
            .unwrap_or_else(config_paths::default_db_path)
    } else {
        path
    }
}

pub(crate) fn legacy_config_path(cli: &Cli) -> PathBuf {
    if cli.config_path.is_empty() {
        paths::default_config_path()
    } else {
        let path = PathBuf::from(&cli.config_path);
        if is_json(&path) {
            path
        } else {
            paths::default_config_path()
        }
    }
}

pub(crate) fn apply_cli_overrides(config: &mut Config, cli: &Cli) {
    if cli.dns_port > 0 {
        let v4 = format!("127.0.0.1:{}", cli.dns_port);
        let v6 = format!("[::1]:{}", cli.dns_port);
        config.dns.udp_addresses = vec![v4.clone(), v6.clone()];
        config.dns.tcp_addresses = vec![v4, v6];
    }
    if !cli.ipc_addr.is_empty() {
        config.ipc.listen_address = cli.ipc_addr.clone();
    }
    if !cli.token.is_empty() {
        config.ipc.auth_token = cli.token.clone();
    }
}

fn has_legacy_files(cli: &Cli) -> bool {
    let data_dir = paths::default_data_dir();
    legacy_config_path(cli).is_file()
        || data_dir.join("dns_state.json").is_file()
        || data_dir.join("cache.json").is_file()
        || data_dir.join("filters").is_dir()
        || data_dir.join("querylog").is_dir()
}

fn prepare_file_storage(cli: &Cli) -> PreparedStorage {
    let config_path = legacy_config_path(cli);
    let mut config = match store::load_config(&config_path) {
        Ok(config) => config,
        Err(error) => {
            eprintln!("[配置] 加载配置失败，使用默认配置: {error}");
            Config::default()
        }
    };
    apply_cli_overrides(&mut config, cli);
    let stores = diting_desktop_app::RuntimeStores::file(config_path.clone(), &config);
    let background_dir = config_path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    PreparedStorage {
        config,
        stores,
        background_dir,
        db: None,
    }
}

pub(crate) fn prepare_storage(
    cli: &Cli,
    include_querylog: bool,
) -> Result<PreparedStorage, String> {
    let data_dir = paths::default_data_dir();
    let config_dir = paths::default_config_dir();
    let legacy_path = legacy_config_path(cli);
    let legacy_config_existed = legacy_path.is_file();
    let db_path = db_path(cli);
    let db = match diting_desktop_sqlite::SqliteDb::open(&db_path) {
        Ok(db) => db,
        Err(error) => {
            eprintln!("[存储] 打开数据库失败: {error}");
            if has_legacy_files(cli) {
                return Ok(prepare_file_storage(cli));
            }
            return Err(error);
        }
    };
    match diting_desktop_sqlite::migrate(&db, &legacy_path, &data_dir, include_querylog) {
        Ok(report) => {
            if report.imported_config
                || report.imported_state
                || report.imported_cache > 0
                || report.imported_lists > 0
                || report.imported_logs > 0
            {
                println!(
                    "[迁移] 完成：配置={} 状态={} 缓存={} 规则源={} 日志={}（跳过 {} 条）删除文件 {} 个",
                    report.imported_config,
                    report.imported_state,
                    report.imported_cache,
                    report.imported_lists,
                    report.imported_logs,
                    report.skipped_logs,
                    report.deleted_files
                );
            }
            for error in &report.errors {
                eprintln!("[迁移] {error}");
            }
        }
        Err(error) => {
            eprintln!("[存储] 迁移失败: {error}");
            let config_available = !legacy_config_existed || legacy_path.is_file();
            if config_available && has_legacy_files(cli) {
                return Ok(prepare_file_storage(cli));
            }
            return Err(error);
        }
    }

    let mut config = match diting_desktop_sqlite::SqliteConfigStore::new(Arc::clone(&db)).load() {
        Ok(config) => config,
        Err(error) => {
            eprintln!("[存储] 读取配置失败: {error}");
            if legacy_path.is_file() {
                return Ok(prepare_file_storage(cli));
            }
            return Err(error.to_string());
        }
    };
    apply_cli_overrides(&mut config, cli);
    let querylog = diting_desktop_app::settings::querylog_settings(&config.query_log);
    let stores = diting_desktop_sqlite::runtime_stores(Arc::clone(&db), &querylog);
    Ok(PreparedStorage {
        config,
        stores,
        background_dir: config_dir,
        db: Some(db),
    })
}

pub(crate) fn prepared_state_store(prepared: &PreparedStorage) -> Arc<dyn StateStore> {
    match &prepared.db {
        Some(db) => Arc::new(diting_desktop_sqlite::SqliteStateStore::new(Arc::clone(db))),
        None => {
            let path = paths::resolve_state_path(&prepared.config.takeover.state_file_path);
            Arc::new(FileStateStore::new(path))
        }
    }
}

pub(crate) fn load_config_for_restore(cli: &Cli) -> Config {
    let db_path = db_path(cli);
    let mut config = if db_path.is_file() {
        match diting_desktop_sqlite::SqliteDb::open(&db_path) {
            Ok(db) => match diting_desktop_sqlite::SqliteConfigStore::new(db).load() {
                Ok(config) => config,
                Err(error) => {
                    eprintln!("[配置] 读取数据库配置失败: {error}");
                    Config::default()
                }
            },
            Err(error) => {
                eprintln!("[配置] 打开数据库失败: {error}");
                Config::default()
            }
        }
    } else {
        match store::load_config(&legacy_config_path(cli)) {
            Ok(config) => config,
            Err(error) => {
                eprintln!("[配置] 加载配置失败，使用默认配置: {error}");
                Config::default()
            }
        }
    };
    apply_cli_overrides(&mut config, cli);
    config
}

pub(crate) fn restore_state_store(cli: &Cli, config: &Config) -> Arc<dyn StateStore> {
    let db_path = db_path(cli);
    let legacy_path = paths::resolve_state_path(&config.takeover.state_file_path);
    if db_path.is_file() {
        if let Ok(db) = diting_desktop_sqlite::SqliteDb::open(&db_path) {
            let store = diting_desktop_sqlite::SqliteStateStore::new(Arc::clone(&db));
            let has_state = store.load().ok().flatten().is_some();
            if !has_state {
                if let Ok(bytes) = std::fs::read(&legacy_path) {
                    if let Ok(state) = serde_json::from_slice::<
                        diting_desktop_api::platform_types::TakeoverState,
                    >(&bytes)
                    {
                        let _ = store.save(&state);
                    }
                }
            }
            return Arc::new(store);
        }
    }
    Arc::new(FileStateStore::new(legacy_path))
}

pub(crate) fn run_reset_password(cli: &Cli, new_password: &str) -> Result<(), String> {
    #[cfg(unix)]
    if cli.config_path.is_empty() && !diting_desktop_platform::privilege::is_elevated() {
        return Err("重置密码需要 root 权限，请通过 SSH root 账户或 sudo 执行".to_string());
    }
    if new_password.chars().count() < 4 {
        return Err("新密码长度不能少于 4 位字符".to_string());
    }

    let prepared = prepare_storage(cli, false)?;
    let mut config = prepared.config;
    let username = if config.web.username.trim().is_empty() {
        "admin".to_string()
    } else {
        config.web.username.trim().to_string()
    };
    let (hash, salt) = hash_password(new_password, "");
    config.web.username = username.clone();
    config.web.password_hash = hash;
    config.web.salt = salt;
    prepared
        .stores
        .config
        .save(&config)
        .map_err(|error| format!("保存管理员新密码失败: {error}"))?;

    if let Some(db) = &prepared.db {
        diting_desktop_sqlite::SqliteSessionStore::new(Arc::clone(db)).clear();
        let _ = db.checkpoint();
    }
    println!("[成功] 管理员账户 [{username}] 的密码已重置，所有已有登录会话已清空。");
    println!("       若谛听服务正在运行，请执行重启使新凭据立即生效。");
    Ok(())
}

#![cfg_attr(windows, windows_subsystem = "windows")]

mod cli;
mod platform_backend;
#[cfg(windows)]
mod windows_host;

use std::sync::Arc;

use async_trait::async_trait;
use cli::{Cli, Command, ServiceAction};
use diting_desktop_api::config::paths as config_paths;
use diting_desktop_api::config::store;
use diting_desktop_api::config::ConfigStore;
use diting_desktop_api::platform_types::AdapterState;
use diting_desktop_app::AppRuntime;
use diting_desktop_platform::error::PlatformResult;
use diting_desktop_platform::paths;
use diting_desktop_platform::state::FileStateStore;
use diting_desktop_platform::traits::{DnsManager, Restorer, StateStore};

struct ManagerRestorer(Arc<dyn DnsManager>);

#[async_trait]
impl Restorer for ManagerRestorer {
    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        self.0.restore_adapters(adapters).await
    }
}

#[tokio::main]
async fn main() {
    #[cfg(windows)]
    windows_host::ensure_std_output();
    let cli = match cli::parse(std::env::args()) {
        Ok(cli) => cli,
        Err(error) => {
            eprintln!("参数错误: {error}");
            std::process::exit(2);
        }
    };
    let result = match cli.command {
        Command::Version => {
            print_version();
            Ok(())
        }
        Command::PortCheck => run_port_check().await,
        Command::Restore => run_restore(&cli).await,
        Command::Service(action) => run_service_action(action, &cli).await,
        Command::Run => run_command(&cli).await,
    };
    if let Err(error) = result {
        eprintln!("[错误] {error}");
        std::process::exit(1);
    }
}

fn print_version() {
    let info = diting_desktop_api::version::info();
    println!(
        "diting-service version {} (built: {}, commit: {})",
        info.version, info.build_time, info.git_commit
    );
    println!(
        "DNS engine: native Rust | Platform: {} | IPC: HTTP/WebSocket",
        platform_backend::platform_name()
    );
}

struct PreparedStorage {
    config: diting_desktop_api::config::Config,
    stores: diting_desktop_app::RuntimeStores,
    background_dir: std::path::PathBuf,
    db: Option<Arc<diting_desktop_sqlite::SqliteDb>>,
}

fn is_json(path: &std::path::Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("json"))
}

fn db_path(cli: &Cli) -> std::path::PathBuf {
    if cli.config_path.is_empty() {
        return config_paths::default_db_path();
    }
    let path = std::path::PathBuf::from(&cli.config_path);
    if is_json(&path) {
        path.parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .map(|parent| parent.join("diting.db"))
            .unwrap_or_else(config_paths::default_db_path)
    } else {
        path
    }
}

fn legacy_config_path(cli: &Cli) -> std::path::PathBuf {
    if cli.config_path.is_empty() {
        paths::default_config_path()
    } else {
        let path = std::path::PathBuf::from(&cli.config_path);
        if is_json(&path) {
            path
        } else {
            paths::default_config_path()
        }
    }
}

fn apply_cli_overrides(config: &mut diting_desktop_api::config::Config, cli: &Cli) {
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
            diting_desktop_api::config::Config::default()
        }
    };
    apply_cli_overrides(&mut config, cli);
    let stores = diting_desktop_app::RuntimeStores::file(config_path.clone(), &config);
    let background_dir = config_path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .map(std::path::Path::to_path_buf)
        .unwrap_or_else(|| std::path::PathBuf::from("."));
    PreparedStorage {
        config,
        stores,
        background_dir,
        db: None,
    }
}

fn prepare_storage(cli: &Cli, include_querylog: bool) -> Result<PreparedStorage, String> {
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
            // 旧配置一旦已被导入并删除，就不能安全回退文件后端（会丢失自定义路径）。
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

fn prepared_state_store(prepared: &PreparedStorage) -> Arc<dyn StateStore> {
    match &prepared.db {
        Some(db) => Arc::new(diting_desktop_sqlite::SqliteStateStore::new(Arc::clone(db))),
        None => {
            let path = paths::resolve_state_path(&prepared.config.takeover.state_file_path);
            Arc::new(FileStateStore::new(path))
        }
    }
}

fn load_config_for_restore(cli: &Cli) -> diting_desktop_api::config::Config {
    let db_path = db_path(cli);
    let mut config = if db_path.is_file() {
        match diting_desktop_sqlite::SqliteDb::open(&db_path) {
            Ok(db) => match diting_desktop_sqlite::SqliteConfigStore::new(db).load() {
                Ok(config) => config,
                Err(error) => {
                    eprintln!("[配置] 读取数据库配置失败: {error}");
                    diting_desktop_api::config::Config::default()
                }
            },
            Err(error) => {
                eprintln!("[配置] 打开数据库失败: {error}");
                diting_desktop_api::config::Config::default()
            }
        }
    } else {
        match store::load_config(&legacy_config_path(cli)) {
            Ok(config) => config,
            Err(error) => {
                eprintln!("[配置] 加载配置失败，使用默认配置: {error}");
                diting_desktop_api::config::Config::default()
            }
        }
    };
    apply_cli_overrides(&mut config, cli);
    config
}

fn restore_state_store(
    cli: &Cli,
    config: &diting_desktop_api::config::Config,
) -> Arc<dyn StateStore> {
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

async fn run_command(cli: &Cli) -> Result<(), String> {
    #[cfg(windows)]
    if let Some(result) = windows_host::try_run_as_service(cli) {
        return result;
    }
    run(cli, wait_for_shutdown()).await
}

pub(crate) async fn run(
    cli: &Cli,
    shutdown: impl std::future::Future<Output = ()>,
) -> Result<(), String> {
    let prepared = prepare_storage(cli, true)?;
    let config = prepared.config.clone();
    let db = prepared.db.clone();
    let state = prepared_state_store(&prepared);
    let manager =
        platform_backend::dns_manager(Arc::clone(&state), diting_desktop_api::version::VERSION);
    let restorer = ManagerRestorer(Arc::clone(&manager));
    match state.check_and_self_heal(Some(&restorer)).await {
        Ok(true) => println!("[自愈] 已恢复上次残留的 DNS 接管配置"),
        Ok(false) => {}
        Err(error) => eprintln!("[自愈检查] 异常: {error}"),
    }

    let handles = platform_backend::platform_handles(state, Arc::clone(&manager));
    let runtime = Arc::new(AppRuntime::with_stores(
        config.clone(),
        prepared.stores,
        prepared.background_dir,
        Some(handles),
    ));
    if let Err(error) = runtime.load_cache() {
        eprintln!("[缓存] 恢复缓存失败，将以空缓存启动: {error}");
    }
    let session_store = db.as_ref().map(|db| {
        Arc::new(diting_desktop_sqlite::SqliteSessionStore::new(Arc::clone(
            db,
        ))) as Arc<dyn diting_desktop_ipc::session::SessionStore>
    });
    let ipc = Arc::new(diting_desktop_ipc::Server::new_with_session_store(
        Arc::clone(&runtime),
        session_store,
    ));
    runtime.set_observer(ipc.query_observer());
    let maintenance = diting_desktop_app::maintenance::Maintenance::spawn(Arc::clone(&runtime));

    match runtime.start_dns_checked().await {
        Ok(()) => {
            let (udp, tcp) =
                diting_desktop_app::controller::effective_listen_addresses(&config.dns);
            println!("[DNS] 已启动: UDP {udp:?} / TCP {tcp:?}");
        }
        Err(error) => eprintln!("[DNS] 启动监听器失败: {error}"),
    }

    ipc.start().await?;
    if let Some(address) = ipc.addr().await {
        println!("[IPC] 管理 API 已监听: http://{address}");
    }

    if config.takeover.auto_takeover_on_start {
        let scanner = platform_backend::adapter_scanner();
        match scanner.active_physical_adapters().await {
            Ok(adapters) => {
                if let Err(error) = manager.takeover(&adapters).await {
                    eprintln!("[接管] 自动接管失败: {error}");
                } else {
                    println!("[接管] 已接管 {} 个网卡", adapters.len());
                }
            }
            Err(error) => eprintln!("[接管] 枚举网卡失败: {error}"),
        }
    }

    shutdown.await;

    ipc.shutdown().await;
    maintenance.shutdown().await;
    runtime.stop_dns().await;
    if let Err(error) = runtime.querylog.close() {
        eprintln!("[查询日志] 关闭失败: {error}");
    }
    if let Err(error) = runtime.save_cache() {
        eprintln!("[缓存] 保存失败: {error}");
    }
    if let Some(db) = &db {
        if let Err(error) = db.checkpoint() {
            eprintln!("[存储] 数据库检查点失败: {error}");
        }
    }
    if manager.is_takeover_active() {
        if let Err(error) = manager.restore().await {
            eprintln!("[接管] 还原系统 DNS 失败: {error}");
        }
    }
    println!("[退出] 谛听 DNS 服务已停止");
    Ok(())
}

async fn wait_for_shutdown() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut terminate = signal(SignalKind::terminate()).expect("SIGTERM handler");
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = terminate.recv() => {}
        }
    }
    #[cfg(windows)]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}

async fn run_port_check() -> Result<(), String> {
    println!("[谛听] 正在探测本地 53 端口占用与冲突...");
    let checker = platform_backend::port_checker();
    let result = checker
        .check_port53()
        .await
        .map_err(|error| format!("探测失败: {error}"))?;
    println!("端口 127.0.0.1:53 绑定可用性: {}", result.available);
    println!(
        "{}: {}",
        platform_backend::port_check_hint(),
        result.has_ics
    );
    println!("--------------------------------------------------");
    println!("诊断报告:\n{}", result.diagnostic);
    println!("--------------------------------------------------");
    for (index, conflict) in result.conflicts.iter().enumerate() {
        println!(
            "  [{}] {} {} (PID: {}, 进程: {}, ICS: {}, 自身: {})",
            index + 1,
            conflict.protocol,
            conflict.local_address,
            conflict.pid,
            conflict.process_name,
            conflict.is_ics,
            conflict.is_self
        );
    }
    Ok(())
}

async fn run_restore(cli: &Cli) -> Result<(), String> {
    println!("[谛听] 正在执行独立离线 DNS 紧急恢复...");
    let config = load_config_for_restore(cli);
    let store = restore_state_store(cli, &config);
    let manager =
        platform_backend::dns_manager(Arc::clone(&store), diting_desktop_api::version::VERSION);
    let restorer = ManagerRestorer(Arc::clone(&manager));
    match store.check_and_self_heal(Some(&restorer)).await {
        Ok(true) => println!("[成功] 已根据残留状态成功恢复系统网卡 DNS！"),
        Ok(false) => println!("[提示] 未检测到残留接管状态文件。"),
        Err(error) => {
            println!("[警告] 快照自愈出现异常: {error}，将继续执行全网卡兜底自愈...")
        }
    }
    match manager.reset_residual_loopback_dns().await {
        Ok(()) => {
            println!("[成功] 已完成全网卡 DNS 状态排查与兜底重置（残留回环已恢复为自动获取）。")
        }
        Err(error) => println!("[警告] 全网卡兜底自愈时出现错误: {error}"),
    }
    let _ = manager.flush_dns_cache().await;
    Ok(())
}

fn service_install_args(cli: &Cli) -> Vec<String> {
    let mut args = Vec::new();
    if !cli.config_path.is_empty() {
        let path = std::path::absolute(&cli.config_path)
            .unwrap_or_else(|_| std::path::PathBuf::from(&cli.config_path));
        args.push("-config".to_string());
        args.push(path.to_string_lossy().into_owned());
    }
    if cli.dns_port > 0 {
        args.push("-port".to_string());
        args.push(cli.dns_port.to_string());
    }
    if !cli.ipc_addr.is_empty() {
        args.push("-ipc-addr".to_string());
        args.push(cli.ipc_addr.clone());
    }
    if !cli.token.is_empty() {
        args.push("-token".to_string());
        args.push(cli.token.clone());
    }
    args
}

async fn run_service_action(action: ServiceAction, cli: &Cli) -> Result<(), String> {
    let manager = platform_backend::service_manager();
    match action {
        ServiceAction::Install => {
            let exe = manager
                .locate_executable()
                .await
                .map_err(|error| format!("定位可执行文件失败: {error}"))?;
            manager
                .install_and_start_with_args(&exe, &service_install_args(cli))
                .await
                .map_err(|error| error.to_string())?;
        }
        ServiceAction::Uninstall => manager.uninstall().await.map_err(|e| e.to_string())?,
        ServiceAction::Start => manager.start().await.map_err(|e| e.to_string())?,
        ServiceAction::Stop => manager.stop().await.map_err(|e| e.to_string())?,
        ServiceAction::Restart => manager.restart().await.map_err(|e| e.to_string())?,
    }
    println!("服务控制操作 [{}] 成功完成", action.as_str());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn service_install_args_forward_cli_overrides() {
        let cli = Cli {
            command: Command::Service(ServiceAction::Install),
            config_path: "config.json".to_string(),
            dns_port: 5353,
            ipc_addr: "127.0.0.1:15354".to_string(),
            token: "secret".to_string(),
        };
        let args = service_install_args(&cli);
        assert_eq!(args[0], "-config");
        assert!(std::path::Path::new(&args[1]).is_absolute());
        let rest: Vec<&str> = args[2..].iter().map(String::as_str).collect();
        assert_eq!(
            rest,
            [
                "-port",
                "5353",
                "-ipc-addr",
                "127.0.0.1:15354",
                "-token",
                "secret"
            ]
        );
    }

    #[test]
    fn service_install_args_are_empty_without_overrides() {
        let cli = Cli {
            command: Command::Service(ServiceAction::Install),
            ..Cli::default()
        };
        assert!(service_install_args(&cli).is_empty());
    }

    #[test]
    fn json_config_path_maps_to_sibling_database() {
        let cli = Cli {
            config_path: std::path::Path::new("data")
                .join("config.json")
                .to_string_lossy()
                .into_owned(),
            ..Cli::default()
        };
        assert_eq!(
            db_path(&cli),
            std::path::Path::new("data").join("diting.db")
        );
        assert_eq!(
            legacy_config_path(&cli),
            std::path::Path::new("data").join("config.json")
        );
    }

    #[test]
    fn database_path_is_used_directly_and_legacy_config_falls_back() {
        let cli = Cli {
            config_path: std::path::Path::new("store")
                .join("custom.db")
                .to_string_lossy()
                .into_owned(),
            ..Cli::default()
        };
        assert_eq!(
            db_path(&cli),
            std::path::Path::new("store").join("custom.db")
        );
        assert_eq!(legacy_config_path(&cli), paths::default_config_path());
    }
}

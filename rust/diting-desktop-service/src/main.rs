#![cfg_attr(windows, windows_subsystem = "windows")]

mod cli;
mod platform_backend;
mod storage_ops;
#[cfg(windows)]
mod windows_host;

use std::sync::Arc;

use async_trait::async_trait;
use cli::{Cli, Command, ServiceAction};
use diting_desktop_api::platform_types::AdapterState;
use diting_desktop_app::AppRuntime;
use diting_desktop_platform::error::PlatformResult;
use diting_desktop_platform::traits::{DnsManager, Restorer};
use storage_ops::{
    load_config_for_restore, prepare_storage, prepared_state_store, restore_state_store,
    run_reset_password,
};

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
    let result = match &cli.command {
        Command::Version => {
            print_version();
            Ok(())
        }
        Command::PortCheck => run_port_check().await,
        Command::Restore => run_restore(&cli).await,
        Command::ResetPassword(password) => run_reset_password(&cli, password),
        Command::Service(action) => run_service_action(*action, &cli).await,
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
    let (manager, openwrt_bridge) = platform_backend::dns_manager(
        Arc::clone(&state),
        &config.openwrt,
        diting_desktop_api::version::VERSION,
    );
    let is_openwrt = platform_backend::is_openwrt();

    // 非 OpenWrt 或尚未开启常驻期望状态时，启动前清理上次异常退出的残留接管；
    // OpenWrt 若用户在管理页已开启常驻（desired_active=true），保留断电前备份并在下方无缝重连。
    if !is_openwrt || !config.openwrt.desired_active {
        let restorer = ManagerRestorer(Arc::clone(&manager));
        match state.check_and_self_heal(Some(&restorer)).await {
            Ok(true) => println!("[自愈] 已恢复上次残留的 DNS 接管配置"),
            Ok(false) => {}
            Err(error) => eprintln!("[自愈检查] 异常: {error}"),
        }
    }

    let handles = platform_backend::platform_handles(state, Arc::clone(&manager), openwrt_bridge);
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

    if is_openwrt {
        if config.openwrt.desired_active {
            match runtime.start_openwrt_dns_and_takeover().await {
                Ok(()) => println!(
                    "[OpenWrt] 已恢复路由器常驻 DNS 解析与接管 (mode={})",
                    config.openwrt.mode
                ),
                Err(error) => eprintln!("[OpenWrt] 开机恢复 DNS 接管失败: {error}"),
            }
        }
    } else if config.takeover.auto_takeover_on_start {
        match runtime.start_dns_checked().await {
            Ok(()) => {
                let (udp, tcp) =
                    diting_desktop_app::controller::effective_listen_addresses(&config.dns);
                println!("[DNS] 已启动: UDP {udp:?} / TCP {tcp:?}");
            }
            Err(error) => eprintln!("[DNS] 启动监听器失败: {error}"),
        }
    }

    ipc.start().await?;
    if let Some(address) = ipc.addr().await {
        println!("[IPC] 管理 API 已监听: http://{address}");
    }

    if !is_openwrt && config.takeover.auto_takeover_on_start && runtime.is_dns_running() {
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
    // 停止进程时还原系统/dnsmasq DNS（OpenWrt 不清除 desired_active，保障重启后仍自动接管，停机期间不断网）。
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
    let checker = platform_backend::port_checker(None);
    let result = checker
        .check_port53()
        .await
        .map_err(|error| format!("探测失败: {error}"))?;
    println!("端口 53 绑定可用性: {}", result.available);
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
            "  [{}] {} {} (PID: {}, 进程: {}, ICS/原生: {}, 自身: {})",
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
    let (manager, _) = platform_backend::dns_manager(
        Arc::clone(&store),
        &config.openwrt,
        diting_desktop_api::version::VERSION,
    );
    let restorer = ManagerRestorer(Arc::clone(&manager));
    match store.check_and_self_heal(Some(&restorer)).await {
        Ok(true) => println!("[成功] 已根据残留状态成功恢复系统 DNS！"),
        Ok(false) => println!("[提示] 未检测到残留接管状态记录。"),
        Err(error) => {
            println!("[警告] 快照自愈出现异常: {error}，将继续执行兜底恢复...")
        }
    }
    match manager.reset_residual_loopback_dns().await {
        Ok(()) => println!("[成功] 已完成 DNS 状态排查与兜底重置。"),
        Err(error) => println!("[警告] 兜底自愈时出现错误: {error}"),
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
    use diting_desktop_api::config::ConfigStore;
    use storage_ops::{db_path, legacy_config_path};

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
    fn reset_password_creates_and_updates_sqlite_credentials() {
        let temp_dir = std::env::temp_dir().join(format!(
            "diting-cli-reset-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        let custom_db = temp_dir.join("diting.db");
        let cli = Cli {
            command: Command::ResetPassword("router1234".into()),
            config_path: custom_db.to_string_lossy().into_owned(),
            ..Cli::default()
        };
        run_reset_password(&cli, "router1234").unwrap();
        let db = diting_desktop_sqlite::SqliteDb::open(&custom_db).unwrap();
        let loaded = diting_desktop_sqlite::SqliteConfigStore::new(db)
            .load()
            .unwrap();
        let auth = diting_desktop_ipc::auth::AuthManager::from_web(&loaded.web);
        assert!(auth.login("admin", "router1234", "192.168.1.2").is_ok());
        let _ = std::fs::remove_dir_all(&temp_dir);
    }
}

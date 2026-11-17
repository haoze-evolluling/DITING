//! `diting-service`: the pure-Rust replacement for the Go desktop service.
//!
//! The binary owns the process lifetime only. Engines live in `diting-desktop-core`, the data plane
//! in `diting-desktop-dns`, the management API in `diting-desktop-ipc` and the OS work in
//! `diting-desktop-platform`.

#![cfg_attr(windows, windows_subsystem = "windows")]

mod cli;
mod platform_backend;

use std::sync::Arc;

use async_trait::async_trait;
use cli::{Cli, Command, ServiceAction};
use diting_desktop_api::config::store;
use diting_desktop_api::platform_types::AdapterState;
use diting_desktop_app::AppRuntime;
use diting_desktop_platform::error::PlatformResult;
use diting_desktop_platform::paths;
use diting_desktop_platform::state::FileStateStore;
use diting_desktop_platform::traits::{DnsManager, Restorer, StateStore};

/// Adapter that lets a manager serve as the state store's restorer on both platforms.
struct ManagerRestorer(Arc<dyn DnsManager>);

#[async_trait]
impl Restorer for ManagerRestorer {
    async fn restore_adapters(&self, adapters: &[AdapterState]) -> PlatformResult<()> {
        self.0.restore_adapters(adapters).await
    }
}

#[tokio::main]
async fn main() {
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
        Command::Service(action) => run_service_action(action).await,
        Command::Run => run(&cli).await,
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

fn load_cli_config(cli: &Cli) -> diting_desktop_api::config::Config {
    let path = if cli.config_path.is_empty() {
        paths::default_config_path()
    } else {
        std::path::PathBuf::from(&cli.config_path)
    };
    let mut config = match store::load_config(&path) {
        Ok(config) => config,
        Err(error) => {
            eprintln!("[配置] 加载配置失败，使用默认配置: {error}");
            diting_desktop_api::config::Config::default()
        }
    };
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
    config
}

async fn run(cli: &Cli) -> Result<(), String> {
    let config = load_cli_config(cli);
    let config_path = if cli.config_path.is_empty() {
        paths::default_config_path()
    } else {
        std::path::PathBuf::from(&cli.config_path)
    };
    let state_path = paths::resolve_state_path(&config.takeover.state_file_path);
    let store = Arc::new(FileStateStore::new(state_path));
    let manager =
        platform_backend::dns_manager(store.clone(), diting_desktop_api::version::VERSION);
    let restorer = ManagerRestorer(Arc::clone(&manager));
    match store.check_and_self_heal(Some(&restorer)).await {
        Ok(true) => println!("[自愈] 已恢复上次残留的 DNS 接管配置"),
        Ok(false) => {}
        Err(error) => eprintln!("[自愈检查] 异常: {error}"),
    }

    let handles = platform_backend::platform_handles(store.clone());
    let runtime = Arc::new(AppRuntime::with_platform(
        config.clone(),
        config_path,
        handles,
    ));
    // The cache is a pure performance facility: a corrupt file must not prevent startup.
    if let Err(error) = runtime.load_cache() {
        eprintln!("[缓存] 恢复缓存失败，将以空缓存启动: {error}");
    }
    let ipc = Arc::new(diting_desktop_ipc::Server::new(Arc::clone(&runtime)));
    runtime.set_observer(ipc.query_observer());
    let maintenance = diting_desktop_app::maintenance::Maintenance::spawn(Arc::clone(&runtime));

    // Go logs a failed start and keeps the management API reachable so the user can diagnose the
    // port conflict from the console; exiting here would make that impossible.
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

    wait_for_shutdown().await;

    // Shutdown order matters: stop accepting management calls, stop background upkeep, then the
    // data plane, then flush the cache and finally release any system DNS takeover.
    ipc.shutdown().await;
    maintenance.shutdown().await;
    runtime.stop_dns().await;
    if let Err(error) = runtime.save_cache() {
        eprintln!("[缓存] 保存失败: {error}");
    }
    // Restore whenever a takeover is active, not only when auto-start was configured: a user may
    // have enabled it by hand while the service was running.
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
    let config = load_cli_config(cli);
    let state_path = paths::resolve_state_path(&config.takeover.state_file_path);
    let store = Arc::new(FileStateStore::new(state_path));
    let manager =
        platform_backend::dns_manager(store.clone(), diting_desktop_api::version::VERSION);
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

async fn run_service_action(action: ServiceAction) -> Result<(), String> {
    let manager = platform_backend::service_manager();
    match action {
        ServiceAction::Install => {
            let exe = manager
                .locate_executable()
                .map_err(|error| format!("定位可执行文件失败: {error}"))?;
            manager
                .install_and_start(&exe)
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

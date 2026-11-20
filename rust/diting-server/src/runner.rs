use std::path::PathBuf;
#[cfg(unix)]
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
#[cfg(unix)]
use std::time::Duration;

use diting_desktop_app::dns_server_config;
use diting_desktop_dns::server::BoundDnsSockets;
use tokio::sync::watch;

use crate::config::ServerConfig;
use crate::control::{bind_socket, run_control_socket, BoundControlSocket};
use crate::paths::ServerPaths;
use crate::runtime::ServerRuntime;

#[derive(Debug, Clone)]
struct Cli {
    data_dir: PathBuf,
    config_path: Option<PathBuf>,
    socket_path: Option<PathBuf>,
    port: u16,
    bind_address: String,
    drop_uid: Option<u32>,
    drop_gid: Option<u32>,
}

pub fn run_from_env() -> Result<(), String> {
    run_with_args(std::env::args().skip(1))
}

pub fn run_with_args(args: impl Iterator<Item = String>) -> Result<(), String> {
    let cli = parse_args(args)?;
    let root = is_effective_root();
    if root && cli.drop_uid.is_none() {
        return Err("Root 启动必须通过 --drop-uid 指定应用 UID".to_string());
    }
    if cli.drop_uid == Some(0) {
        return Err("拒绝降权到 UID 0".to_string());
    }

    let paths = ServerPaths::new(&cli.data_dir)
        .with_overrides(cli.config_path.as_deref(), cli.socket_path.as_deref());
    let config = ServerConfig::load(&paths, cli.port, root, &cli.bind_address)?;
    paths
        .ensure_dirs()
        .map_err(|error| format!("创建服务器目录失败: {error}"))?;

    let dns_config = dns_server_config(&config.desktop_config());
    let dns_sockets = BoundDnsSockets::bind(&dns_config).map_err(|error| {
        if root && cli.port == 53 {
            format!("{error}；53 端口绑定失败，请改用非 Root 的 1053 端口重试")
        } else {
            error
        }
    })?;
    if root {
        let uid = cli.drop_uid.expect("checked above");
        let gid = cli.drop_gid.unwrap_or(uid);
        chown_tree(&paths.data_dir, uid, gid)?;
        let control = bind_socket(&paths.socket_path, Some(uid), Some(gid))?;
        drop_privileges(uid, gid)?;
        return serve(config, paths, dns_sockets, control);
    }
    let control = bind_socket(&paths.socket_path, None, None)?;
    serve(config, paths, dns_sockets, control)
}

fn serve(
    config: ServerConfig,
    paths: ServerPaths,
    dns_sockets: BoundDnsSockets,
    control: BoundControlSocket,
) -> Result<(), String> {
    config.save(&paths.config_path)?;
    install_signal_handlers()?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|error| format!("创建服务器运行时失败: {error}"))?;
    runtime.block_on(async move {
        let server = Arc::new(ServerRuntime::new(paths, config)?);
        server.start(dns_sockets).await?;
        server.save_initial_config()?;
        let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
        let control_server = Arc::clone(&server);
        let control_tx = shutdown_tx.clone();
        let mut control_task =
            tokio::spawn(
                async move { run_control_socket(control, control_server, control_tx).await },
            );
        let mut control_done = false;
        let status = server.status(true);
        println!(
            "SERVER_READY {}",
            serde_json::json!({
                "port": status.port,
                "root": status.root,
                "addresses": status.addresses,
                "socket": server.paths().socket_path,
                "pid": std::process::id(),
            })
        );

        tokio::select! {
            changed = shutdown_rx.changed() => {
                let _ = changed;
            }
            _ = wait_for_signal() => {}
            result = &mut control_task => {
                control_done = true;
                if let Ok(Err(error)) = result {
                    eprintln!("[控制] {error}");
                }
            }
        }
        let _ = shutdown_tx.send(true);
        if !control_done {
            control_task.abort();
            let _ = control_task.await;
        }
        server.shutdown().await;
        let _ = std::fs::remove_file(&server.paths().socket_path);
        println!("[退出] 服务器模式已停止");
        Ok(())
    })
}

async fn wait_for_signal() {
    #[cfg(unix)]
    {
        while !STOP_SIGNAL.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}

#[cfg(unix)]
static STOP_SIGNAL: AtomicBool = AtomicBool::new(false);

#[cfg(unix)]
extern "C" fn handle_stop_signal(_signal: libc::c_int) {
    STOP_SIGNAL.store(true, Ordering::SeqCst);
}

#[cfg(unix)]
fn install_signal_handlers() -> Result<(), String> {
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = handle_stop_signal as *const () as libc::sighandler_t;
        action.sa_flags = libc::SA_RESTART;
        libc::sigemptyset(&mut action.sa_mask);
        for signal in [libc::SIGTERM, libc::SIGINT] {
            if libc::sigaction(signal, &action, std::ptr::null_mut()) != 0 {
                return Err(format!(
                    "安装信号处理器失败 (signal {signal}): {}",
                    std::io::Error::last_os_error()
                ));
            }
        }
    }
    Ok(())
}

#[cfg(not(unix))]
fn install_signal_handlers() -> Result<(), String> {
    Ok(())
}

fn parse_args(args: impl Iterator<Item = String>) -> Result<Cli, String> {
    let mut cli = Cli {
        data_dir: std::env::temp_dir().join("diting-server"),
        config_path: None,
        socket_path: None,
        port: 1053,
        bind_address: "0.0.0.0".to_string(),
        drop_uid: None,
        drop_gid: None,
    };
    let values: Vec<String> = args.collect();
    let mut index = 0;
    while index < values.len() {
        let flag = values[index].as_str();
        let value = |index: usize| -> Result<&str, String> {
            values
                .get(index + 1)
                .map(String::as_str)
                .ok_or_else(|| format!("参数 {flag} 缺少取值"))
        };
        match flag {
            "--data-dir" => {
                cli.data_dir = PathBuf::from(value(index)?);
                index += 2;
            }
            "--config" => {
                cli.config_path = Some(PathBuf::from(value(index)?));
                index += 2;
            }
            "--socket" => {
                cli.socket_path = Some(PathBuf::from(value(index)?));
                index += 2;
            }
            "--bind" => {
                cli.bind_address = value(index)?.to_string();
                index += 2;
            }
            "--port" => {
                cli.port = value(index)?
                    .parse()
                    .map_err(|_| "端口必须是 1–65535 的数字".to_string())?;
                index += 2;
            }
            "--drop-uid" => {
                cli.drop_uid = Some(parse_id(value(index)?)?);
                index += 2;
            }
            "--drop-gid" => {
                cli.drop_gid = Some(parse_id(value(index)?)?);
                index += 2;
            }
            "--help" | "-h" => {
                println!(
                    "diting-server --data-dir DIR [--config FILE] [--socket FILE] \
                     [--port 1053] [--bind 0.0.0.0] [--drop-uid UID] [--drop-gid GID]"
                );
                std::process::exit(0);
            }
            other => return Err(format!("未知参数: {other}")),
        }
    }
    if cli.port == 0 {
        return Err("端口必须在 1–65535 之间".to_string());
    }
    Ok(cli)
}

fn parse_id(raw: &str) -> Result<u32, String> {
    raw.parse().map_err(|_| format!("无效的 UID/GID: {raw}"))
}

#[cfg(unix)]
fn is_effective_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

#[cfg(not(unix))]
fn is_effective_root() -> bool {
    false
}

#[cfg(unix)]
fn drop_privileges(uid: u32, gid: u32) -> Result<(), String> {
    #[cfg(target_os = "android")]
    let supplementary = [ANDROID_AID_INET];
    #[cfg(not(target_os = "android"))]
    let supplementary: [libc::gid_t; 0] = [];
    let groups = unsafe {
        libc::setgroups(
            supplementary.len(),
            if supplementary.is_empty() {
                std::ptr::null()
            } else {
                supplementary.as_ptr()
            },
        )
    };
    if groups != 0 {
        return Err(format!(
            "设置附加组失败: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { libc::setgid(gid) } != 0 {
        return Err(format!(
            "降权设置 GID 失败: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { libc::setuid(uid) } != 0 {
        return Err(format!(
            "降权设置 UID 失败: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { libc::geteuid() } == 0 || unsafe { libc::getegid() } == 0 {
        return Err("降权后仍为 Root，拒绝继续运行".to_string());
    }
    Ok(())
}

#[cfg(target_os = "android")]
const ANDROID_AID_INET: libc::gid_t = 3003;

#[cfg(not(unix))]
fn drop_privileges(_uid: u32, _gid: u32) -> Result<(), String> {
    Err("当前平台不支持降权".to_string())
}

#[cfg(unix)]
fn chown_tree(path: &std::path::Path, uid: u32, gid: u32) -> Result<(), String> {
    use std::os::unix::ffi::OsStrExt;
    let entries = std::fs::read_dir(path)
        .map_err(|error| format!("读取数据目录失败 ({}): {error}", path.display()))?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let child = entry.path();
        let metadata = std::fs::symlink_metadata(&child)
            .map_err(|error| format!("读取 {} 失败: {error}", child.display()))?;
        if metadata.file_type().is_dir() {
            chown_tree(&child, uid, gid)?;
        }
        if metadata.file_type().is_symlink() {
            continue;
        }
        let c_path = std::ffi::CString::new(child.as_os_str().as_bytes())
            .map_err(|_| format!("路径包含空字节: {}", child.display()))?;
        if unsafe { libc::chown(c_path.as_ptr(), uid, gid) } != 0 {
            return Err(format!(
                "设置 {} 所有者失败: {}",
                child.display(),
                std::io::Error::last_os_error()
            ));
        }
    }
    let c_path = std::ffi::CString::new(path.as_os_str().as_bytes())
        .map_err(|_| format!("路径包含空字节: {}", path.display()))?;
    if unsafe { libc::chown(c_path.as_ptr(), uid, gid) } != 0 {
        return Err(format!(
            "设置 {} 所有者失败: {}",
            path.display(),
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

#[cfg(not(unix))]
fn chown_tree(_path: &std::path::Path, _uid: u32, _gid: u32) -> Result<(), String> {
    Ok(())
}

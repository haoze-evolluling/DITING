//! Filesystem Unix-domain socket implementation.

use std::ffi::CString;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::Arc;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::watch;

use super::handle_request;
use crate::protocol::{encode_response, parse_request, Response};
use crate::runtime::ServerRuntime;

pub struct BoundControlSocket {
    listener: std::os::unix::net::UnixListener,
}

/// Creates the private control socket before privileges are dropped. Ownership is transferred to
/// the app UID so the Flutter process can talk to a process that is otherwise unprivileged.
pub fn bind_socket(
    path: &Path,
    uid: Option<u32>,
    gid: Option<u32>,
) -> Result<BoundControlSocket, String> {
    if path.exists() {
        std::fs::remove_file(path).map_err(|error| format!("清理旧控制套接字失败: {error}"))?;
    }
    let listener = std::os::unix::net::UnixListener::bind(path)
        .map_err(|error| format!("创建控制套接字失败: {error}"))?;
    listener
        .set_nonblocking(true)
        .map_err(|error| format!("配置控制套接字失败: {error}"))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
        .map_err(|error| format!("设置控制套接字权限失败: {error}"))?;
    if uid.is_some() || gid.is_some() {
        chown(path, uid, gid)?;
    }
    Ok(BoundControlSocket { listener })
}

fn chown(path: &Path, uid: Option<u32>, gid: Option<u32>) -> Result<(), String> {
    let path = CString::new(path.as_os_str().as_bytes())
        .map_err(|_| "控制套接字路径包含空字节".to_string())?;
    let uid = uid.map_or(!0, |value| value);
    let gid = gid.map_or(!0, |value| value);
    let result = unsafe { libc::chown(path.as_ptr(), uid, gid) };
    if result == 0 {
        Ok(())
    } else {
        Err(format!(
            "设置控制套接字所有者失败: {}",
            std::io::Error::last_os_error()
        ))
    }
}

pub async fn run_control_socket(
    bound: BoundControlSocket,
    runtime: Arc<ServerRuntime>,
    shutdown: watch::Sender<bool>,
) -> Result<(), String> {
    let mut shutdown_rx = shutdown.subscribe();
    let listener = tokio::net::UnixListener::from_std(bound.listener)
        .map_err(|error| format!("启动控制套接字失败: {error}"))?;
    let mut tasks = tokio::task::JoinSet::new();
    loop {
        tokio::select! {
            changed = shutdown_rx.changed() => {
                if changed.is_err() || *shutdown_rx.borrow() {
                    break;
                }
            }
            accepted = listener.accept() => {
                let Ok((stream, _)) = accepted else { continue };
                let runtime = Arc::clone(&runtime);
                let sender = shutdown.clone();
                tasks.spawn(async move {
                    let _ = serve(stream, runtime, sender).await;
                });
            }
        }
    }
    tasks.abort_all();
    while tasks.join_next().await.is_some() {}
    Ok(())
}

async fn serve(
    stream: tokio::net::UnixStream,
    runtime: Arc<ServerRuntime>,
    shutdown: watch::Sender<bool>,
) -> std::io::Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();
    if reader.read_line(&mut line).await? == 0 {
        return Ok(());
    }
    let (response, stop) = match parse_request(&line) {
        Ok(request) => {
            let (response, stop) = handle_request(&runtime, request).await;
            (response, stop)
        }
        Err(error) => (
            Response::error(serde_json::Value::Null, error.code, error.message),
            false,
        ),
    };
    let encoded = encode_response(&response).unwrap_or_else(|_| {
        r#"{"id":null,"ok":false,"error":{"code":"encode_failed","message":"encode failed"}}"#
            .to_string()
    });
    writer.write_all(encoded.as_bytes()).await?;
    writer.write_all(b"\n").await?;
    writer.flush().await?;
    if stop {
        let _ = shutdown.send(true);
    }
    Ok(())
}

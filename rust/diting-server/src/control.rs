use std::sync::Arc;

use serde_json::{json, Value};
#[cfg(not(unix))]
use tokio::sync::watch;

use crate::config::ServerConfig;
use crate::protocol::{Request, Response};
use crate::runtime::{parse_qtype, ServerRuntime};

pub async fn handle_request(runtime: &Arc<ServerRuntime>, request: Request) -> (Response, bool) {
    let id = request.id.clone();
    let result = match request.method.as_str() {
        "status" => {
            let running = runtime.is_running().await;
            Ok(json!(runtime.status(running)))
        }
        "get_config" => Ok(json!(runtime.config())),
        "update_config" => update_config(runtime, request.params).map(|config| json!(config)),
        "stats" => Ok(json!(runtime.stats())),
        "query_log" => query_log(runtime, request.params),
        "clear_query_log" => runtime.clear_query_log(),
        "filter_refresh" => {
            let filter_id = request
                .params
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("");
            runtime
                .refresh_filter(filter_id)
                .await
                .map(|config| json!(config.filter))
        }
        "filter_check" => filter_check(runtime, request.params),
        "shutdown" => Ok(json!({"stopping": true})),
        other => Err(format!("未知的控制方法: {other}")),
    };
    let response = match result {
        Ok(value) => Response::ok(id, value),
        Err(message) => Response::error(id, "request_failed", message),
    };
    (response, request.method == "shutdown")
}

fn update_config(runtime: &Arc<ServerRuntime>, params: Value) -> Result<ServerConfig, String> {
    let value = params.get("config").cloned().unwrap_or(params);
    let next = serde_json::from_value::<ServerConfig>(value)
        .map_err(|error| format!("无效的服务器配置: {error}"))?;
    runtime.replace_config(next)
}

fn query_log(runtime: &Arc<ServerRuntime>, params: Value) -> Result<Value, String> {
    let query = serde_json::from_value::<diting_desktop_core::querylog::SearchQuery>(params)
        .map_err(|error| format!("无效的日志筛选条件: {error}"))?;
    Ok(runtime.query_log(query))
}

fn filter_check(runtime: &Arc<ServerRuntime>, params: Value) -> Result<Value, String> {
    let domain = params
        .get("domain")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|domain| !domain.is_empty())
        .ok_or_else(|| "缺少待检测域名".to_string())?;
    let qtype = parse_qtype(params.get("qtype").and_then(Value::as_str));
    Ok(runtime.filter_check(domain, qtype))
}

#[cfg(unix)]
mod unix_socket;
#[cfg(unix)]
pub use unix_socket::{bind_socket, run_control_socket, BoundControlSocket};

#[cfg(not(unix))]
pub struct BoundControlSocket;

#[cfg(not(unix))]
pub fn bind_socket(
    _path: &std::path::Path,
    _uid: Option<u32>,
    _gid: Option<u32>,
) -> Result<BoundControlSocket, String> {
    Err("Unix 控制套接字仅在 Android/Linux 上可用".to_string())
}

#[cfg(not(unix))]
pub async fn run_control_socket(
    _bound: BoundControlSocket,
    _runtime: Arc<ServerRuntime>,
    _shutdown: watch::Sender<bool>,
) -> Result<(), String> {
    Err("Unix 控制套接字仅在 Android/Linux 上可用".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::paths::ServerPaths;

    fn runtime(tag: &str) -> Arc<ServerRuntime> {
        let paths = ServerPaths::new(std::env::temp_dir().join(format!(
            "diting-server-control-{tag}-{}",
            std::process::id()
        )));
        let mut config = ServerConfig::default();
        config.normalize(&paths, 1053, false, "0.0.0.0").unwrap();
        Arc::new(ServerRuntime::new(paths, config).unwrap())
    }

    #[tokio::test]
    async fn status_get_config_and_unknown_methods() {
        let runtime = runtime("status");
        let (response, stop) = handle_request(
            &runtime,
            Request {
                id: Value::from(1),
                method: "status".to_string(),
                params: json!({}),
            },
        )
        .await;
        assert!(response.ok);
        assert!(!stop);
        assert_eq!(response.result.unwrap()["port"], 1053);

        let (response, _) = handle_request(
            &runtime,
            Request {
                id: Value::from(2),
                method: "unknown".to_string(),
                params: json!({}),
            },
        )
        .await;
        assert!(!response.ok);
        assert_eq!(response.error.unwrap().code, "request_failed");
    }

    #[tokio::test]
    async fn filter_check_requires_a_domain() {
        let runtime = runtime("filter");
        let (response, _) = handle_request(
            &runtime,
            Request {
                id: Value::from(3),
                method: "filter_check".to_string(),
                params: json!({}),
            },
        )
        .await;
        assert!(!response.ok);
        assert!(response.error.unwrap().message.contains("域名"));
    }
}

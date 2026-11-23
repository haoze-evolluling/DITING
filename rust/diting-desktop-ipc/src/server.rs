use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock, Weak};

use base64::Engine;
use http_body_util::{BodyExt, Full};
use hyper::body::{Bytes, Incoming};
use hyper::header::{HeaderMap, HeaderValue};
use hyper::http::StatusCode;
use hyper::{Request, Response};
use hyper_util::rt::{TokioExecutor, TokioIo};
use hyper_util::server::conn::auto::Builder;
use sha1::{Digest, Sha1};
use tokio::net::TcpListener;
use tokio::sync::{oneshot, Mutex};
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::protocol::Role;
use tokio_tungstenite::WebSocketStream;

use diting_desktop_api::config::IPCConfig;
use diting_desktop_dns::stages::metrics::QueryObserver;

use crate::auth::AuthManager;
use crate::handlers::{self, Ctx, Resp};
use crate::router;
use crate::session::SessionStore;
use crate::ws::{self, DesktopQueryObserver, WsHub};
use crate::AppRuntime;

pub const MAX_BODY_BYTES: usize = 4 << 20;

const WEBSOCKET_GUID: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

pub struct Server {
    runtime: Arc<AppRuntime>,
    auth: Arc<AuthManager>,
    hub: Arc<WsHub>,
    listener_addr: Mutex<Option<SocketAddr>>,
    shutdown: Mutex<Option<oneshot::Sender<()>>>,
    join: Mutex<Option<JoinHandle<()>>>,
    started: AtomicBool,
    self_ref: OnceLock<Weak<Server>>,
}

impl Server {
    pub fn new(runtime: Arc<AppRuntime>) -> Self {
        Self::new_with_session_store(runtime, None)
    }

    pub fn new_with_session_store(
        runtime: Arc<AppRuntime>,
        session_store: Option<Arc<dyn SessionStore>>,
    ) -> Self {
        Self::with_hub_and_session_store(runtime, Arc::new(WsHub::new()), session_store)
    }

    pub fn with_hub(runtime: Arc<AppRuntime>, hub: Arc<WsHub>) -> Self {
        Self::with_hub_and_session_store(runtime, hub, None)
    }

    pub fn with_hub_and_session_store(
        runtime: Arc<AppRuntime>,
        hub: Arc<WsHub>,
        session_store: Option<Arc<dyn SessionStore>>,
    ) -> Self {
        let config = runtime.config();
        let auth = Arc::new(AuthManager::from_web_with_store(&config.web, session_store));
        Self {
            runtime,
            auth,
            hub,
            listener_addr: Mutex::new(None),
            shutdown: Mutex::new(None),
            join: Mutex::new(None),
            started: AtomicBool::new(false),
            self_ref: OnceLock::new(),
        }
    }

    pub fn runtime(&self) -> &Arc<AppRuntime> {
        &self.runtime
    }

    pub fn auth(&self) -> &Arc<AuthManager> {
        &self.auth
    }

    pub fn hub(&self) -> &Arc<WsHub> {
        &self.hub
    }

    pub fn ipc_config(&self) -> IPCConfig {
        self.runtime.with_config(|config| config.ipc.clone())
    }

    pub fn query_observer(&self) -> Arc<dyn QueryObserver> {
        Arc::new(DesktopQueryObserver::new(
            Arc::clone(&self.hub),
            Arc::clone(&self.runtime.querylog),
            Arc::clone(&self.runtime),
        ))
    }

    pub async fn start(self: &Arc<Self>) -> Result<(), String> {
        if self.started.swap(true, Ordering::SeqCst) {
            return Err("IPC 服务已启动".to_string());
        }
        let _ = self.self_ref.set(Arc::downgrade(self));
        let (listener, local) = match self.bind_configured().await {
            Ok(bound) => bound,
            Err(error) => {
                self.started.store(false, Ordering::SeqCst);
                return Err(error);
            }
        };
        *self.listener_addr.lock().await = Some(local);
        let (sender, receiver) = oneshot::channel::<()>();
        *self.shutdown.lock().await = Some(sender);
        *self.join.lock().await = Some(spawn_accept_loop(Arc::clone(self), listener, receiver));
        Ok(())
    }

    pub async fn restart(self: &Arc<Self>) -> Result<SocketAddr, String> {
        if let Some(sender) = self.shutdown.lock().await.take() {
            let _ = sender.send(());
        }
        if let Some(handle) = self.join.lock().await.take() {
            let _ = tokio::time::timeout(std::time::Duration::from_secs(1), handle).await;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        let (listener, local) = match self.bind_configured().await {
            Ok(bound) => bound,
            Err(error) => {
                *self.listener_addr.lock().await = None;
                self.started.store(false, Ordering::SeqCst);
                return Err(error);
            }
        };
        let (sender, receiver) = oneshot::channel::<()>();
        *self.shutdown.lock().await = Some(sender);
        *self.join.lock().await = Some(spawn_accept_loop(Arc::clone(self), listener, receiver));
        *self.listener_addr.lock().await = Some(local);
        self.started.store(true, Ordering::SeqCst);
        Ok(local)
    }

    pub async fn restart_listener(&self) -> Result<SocketAddr, String> {
        let Some(server) = self.self_ref.get().and_then(Weak::upgrade) else {
            return Err("IPC 服务尚未启动".to_string());
        };
        server.restart().await
    }

    async fn bind_configured(&self) -> Result<(TcpListener, SocketAddr), String> {
        let address = self.runtime.config().ipc.listen_address;
        let address = if address.is_empty() {
            "127.0.0.1:15353".to_string()
        } else {
            address
        };
        let listener = TcpListener::bind(&address)
            .await
            .map_err(|error| format!("绑定 IPC 端口失败 ({address}): {error}"))?;
        let local = listener
            .local_addr()
            .map_err(|error| format!("读取 IPC 监听地址失败: {error}"))?;
        Ok((listener, local))
    }

    pub async fn shutdown(&self) {
        if let Some(sender) = self.shutdown.lock().await.take() {
            let _ = sender.send(());
        }
        if let Some(handle) = self.join.lock().await.take() {
            if tokio::time::timeout(std::time::Duration::from_secs(3), handle)
                .await
                .is_err()
            {}
        }
        self.started.store(false, Ordering::SeqCst);
    }

    pub async fn addr(&self) -> Option<SocketAddr> {
        *self.listener_addr.lock().await
    }

    pub fn verify_token(&self, token: &str, remote: SocketAddr, headers: &HeaderMap) -> bool {
        // 每个请求都会走这里，只从配置里取需要的两项，而不是整份 `Config` 克隆。
        let (configured, matches) = self.runtime.with_config(|config| {
            let auth = &config.ipc.auth_token;
            (!auth.is_empty(), auth == token)
        });
        if configured && matches {
            return true;
        }
        if !token.is_empty() && self.auth.is_authenticated(token) {
            return true;
        }
        if !configured && remote.ip().is_loopback() {
            let origin = headers
                .get("origin")
                .and_then(|value| value.to_str().ok())
                .unwrap_or("");
            let host = headers.get("host").and_then(|value| value.to_str().ok());
            return crate::cors::is_trusted_origin(origin, host);
        }
        false
    }
}

fn spawn_accept_loop(
    server: Arc<Server>,
    listener: TcpListener,
    mut receiver: oneshot::Receiver<()>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = &mut receiver => break,
                accepted = listener.accept() => {
                    let Ok((stream, remote)) = accepted else { continue };
                    let server = Arc::clone(&server);
                    tokio::spawn(async move {
                        let service = hyper::service::service_fn(move |request| {
                            serve_request(request, remote, Arc::clone(&server))
                        });
                        let builder = Builder::new(TokioExecutor::new());
                        let _ = builder
                            .serve_connection_with_upgrades(TokioIo::new(stream), service)
                            .await;
                    });
                }
            }
        }
    })
}

async fn serve_request(
    request: Request<Incoming>,
    remote: SocketAddr,
    server: Arc<Server>,
) -> Result<Response<Full<Bytes>>, hyper::Error> {
    let response = handle_request(&server, request, remote).await;
    Ok(response)
}

async fn handle_request(server: &Server, request: Request<Incoming>, remote: SocketAddr) -> Resp {
    let method = request.method().clone();
    let uri = request.uri().clone();
    let headers = request.headers().clone();
    let path = uri.path().to_string();

    if method == hyper::http::Method::OPTIONS {
        let origin = headers
            .get("origin")
            .and_then(|value| value.to_str().ok())
            .unwrap_or("");
        let host = headers.get("host").and_then(|value| value.to_str().ok());
        let status = crate::cors::preflight_status(origin, host).unwrap_or(403);
        let mut response = Response::new(Full::new(Bytes::new()));
        *response.status_mut() = StatusCode::from_u16(status).unwrap_or(StatusCode::FORBIDDEN);
        return with_cors(response, &headers);
    }

    if path == "/api/v1/events" {
        return with_cors(handle_websocket(server, request, remote).await, &headers);
    }

    let body = match read_body(request.into_body()).await {
        Ok(body) => body,
        Err(response) => return with_cors(response, &headers),
    };
    let ctx = Ctx::new(&method, &uri, &headers, remote, &body);

    let response = if path.starts_with("/api/") {
        match router::auth_requirement(&path) {
            router::Auth::Required if !handlers::verified(server, &ctx) => {
                handlers::unauthorized("unauthorized: missing or invalid authentication token")
            }
            _ => router::dispatch(server, &ctx, &path).await,
        }
    } else {
        crate::static_files::serve(&path)
    };

    with_cors(response, &headers)
}

#[allow(clippy::result_large_err)]
async fn read_body(mut body: Incoming) -> Result<Bytes, Resp> {
    let mut collected = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame =
            frame.map_err(|error| handlers::bad_request(format!("读取请求体失败: {error}")))?;
        if let Some(data) = frame.data_ref() {
            if collected.len() + data.len() > MAX_BODY_BYTES {
                return Err(handlers::bad_request("请求体超过 4 MiB 上限"));
            }
            collected.extend_from_slice(data);
        }
    }
    Ok(Bytes::from(collected))
}

fn with_cors(mut response: Resp, headers: &HeaderMap) -> Resp {
    let origin = headers
        .get("origin")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    let host = headers.get("host").and_then(|value| value.to_str().ok());
    crate::cors::apply_headers(response.headers_mut(), origin, host);
    response
}

async fn handle_websocket(
    server: &Server,
    mut request: Request<Incoming>,
    remote: SocketAddr,
) -> Resp {
    let headers = request.headers().clone();
    let uri = request.uri().clone();
    let ctx = Ctx::new(request.method(), &uri, &headers, remote, &[]);
    let origin = headers
        .get("origin")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    let host = headers.get("host").and_then(|value| value.to_str().ok());
    if !crate::cors::is_trusted_origin(origin, host) {
        return handlers::plain_text(StatusCode::FORBIDDEN, "forbidden origin");
    }
    if !handlers::verified(server, &ctx) {
        return handlers::plain_text(
            StatusCode::UNAUTHORIZED,
            "unauthorized: missing or invalid authentication token",
        );
    }
    let is_upgrade = headers
        .get("upgrade")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false);
    if !is_upgrade {
        return handlers::plain_text(StatusCode::BAD_REQUEST, "websocket upgrade required");
    }
    let Some(key) = headers
        .get("sec-websocket-key")
        .and_then(|value| value.to_str().ok())
        .map(str::to_string)
    else {
        return handlers::plain_text(StatusCode::BAD_REQUEST, "missing Sec-WebSocket-Key");
    };
    drop(ctx);

    let upgrade = hyper::upgrade::on(&mut request);
    let (id, receiver) = server.hub.register();
    let hub = Arc::clone(server.hub());
    tokio::spawn(async move {
        if let Ok(upgraded) = upgrade.await {
            let stream =
                WebSocketStream::from_raw_socket(TokioIo::new(upgraded), Role::Server, None).await;
            ws::run_client(stream, receiver).await;
        }
        hub.unregister(id);
    });

    let mut hasher = Sha1::new();
    hasher.update(key.as_bytes());
    hasher.update(WEBSOCKET_GUID.as_bytes());
    let accept = base64::engine::general_purpose::STANDARD.encode(hasher.finalize());

    let mut response = Response::new(Full::new(Bytes::new()));
    *response.status_mut() = StatusCode::SWITCHING_PROTOCOLS;
    let response_headers = response.headers_mut();
    response_headers.insert(
        hyper::header::CONNECTION,
        HeaderValue::from_static("Upgrade"),
    );
    response_headers.insert(
        hyper::header::UPGRADE,
        HeaderValue::from_static("websocket"),
    );
    if let Ok(value) = HeaderValue::from_str(&accept) {
        response_headers.insert(hyper::header::SEC_WEBSOCKET_ACCEPT, value);
    }
    response
}

//! The outbound transports: direct, SOCKS5 and HTTP CONNECT, with the per-UID proxy scope.
//!
//! `flow_outbound.go` + `engine_outbound_scope.go` in Rust. The decision half is unchanged:
//! [`diting_proxy_core`] normalizes the config and speaks SOCKS5 / HTTP CONNECT on the wire,
//! [`diting_gate_core::route`] decides whether a flow of a given UID uses the proxy. This module
//! owns the sockets, the deadlines, the status callback and the two transports.
//!
//! ```text
//! Route::Direct  → create socket → VpnService.protect → connect            (protected)
//! Route::Proxy   → protected connect to the proxy → SOCKS5 / HTTP CONNECT → target
//! UDP + SOCKS5   → UDP ASSOCIATE over a control connection → framed datagrams
//! UDP + HTTP     → error: HTTP CONNECT has no datagram mode
//! ```
//!
//! # Scope
//!
//! `enabled:false` is direct for everything. `scope:"all"` proxies every flow. `scope:"apps"` proxies
//! only the selected UIDs, and an unattributable flow (`uid = -1`) stays direct — the rule
//! [`diting_gate_core::route::proxies_uid`] already encodes.
//!
//! # Status
//!
//! `OutboundProxyStatusCallback` sees `disabled`, `connecting`, `ready` and `error`, deduplicated on
//! `(state, message)` like Go's `proxyFlowOutbound.status`. `connecting` is emitted by
//! [`crate::engine::Engine::start_full_with_link`], the rest by the dials themselves.

pub mod handshake;
pub mod udp;

use std::net::SocketAddr;
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;

use diting_gate_core::route as scope;
use diting_proxy_core::config::{self, NormalizedConfig, ProxyConfig as KernelConfig};
use tokio::net::TcpStream;

use crate::protect::ProtectorHandle;
use crate::resolver::dial;

/// `flowDialTimeout`: one upstream dial, including the proxy handshake.
pub const DIAL_TIMEOUT: Duration = Duration::from_secs(10);

/// Which transport a flow uses.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Route {
    Direct,
    Proxy,
}

/// One proxy configuration. The credentials are kept here because the kernel's normalized config
/// deliberately drops them.
#[derive(Clone, Debug, Default)]
pub struct Config {
    enabled: bool,
    protocol: String,
    host: String,
    port: i64,
    username: String,
    password: String,
    scope: String,
    uids: Vec<i64>,
}

/// The JSON shape `ConfigureOutboundProxy` receives; the kernel validates and normalizes it.
#[derive(Debug, Default, serde::Deserialize)]
#[serde(default)]
struct RawConfig {
    enabled: bool,
    protocol: String,
    host: String,
    port: i64,
    username: String,
    password: String,
    scope: String,
    uids: Vec<i64>,
}

impl Config {
    /// `parseOutboundProxyConfig`: blank means disabled, otherwise the kernel validates.
    pub fn parse(raw: &str) -> Result<Self, String> {
        if raw.trim().is_empty() {
            return Ok(Self::default());
        }
        let decoded: RawConfig = serde_json::from_str(raw)
            .map_err(|error| format!("invalid outbound proxy config: {error}"))?;
        let NormalizedConfig {
            enabled,
            protocol,
            host,
            port,
            scope,
            uids,
            ..
        } = config::normalize(KernelConfig {
            enabled: decoded.enabled,
            protocol: decoded.protocol,
            host: decoded.host,
            port: decoded.port,
            username: decoded.username.clone(),
            password: decoded.password.clone(),
            scope: decoded.scope,
            uids: decoded.uids,
        })?;
        Ok(Self {
            enabled,
            protocol,
            host,
            port,
            username: decoded.username,
            password: decoded.password,
            scope,
            uids,
        })
    }

    pub fn enabled(&self) -> bool {
        self.enabled
    }

    /// Whether the engine's own DNS upstream dials follow the proxy (`resolverOutbound`): the whole
    /// point of `scope:"all"` is that not even the resolver's queries leave directly.
    pub fn resolver_uses_proxy(&self) -> bool {
        self.enabled && !self.per_app()
    }

    /// `perApp`: only the selected UIDs are proxied.
    pub fn per_app(&self) -> bool {
        scope::per_app(self.enabled, &self.scope)
    }

    /// The transport for a flow owned by `uid`.
    pub fn route_for(&self, uid: i32) -> Route {
        if !self.enabled {
            return Route::Direct;
        }
        if scope::proxies_uid(self.enabled, &self.scope, i64::from(uid), &self.uids) {
            Route::Proxy
        } else {
            Route::Direct
        }
    }

    /// `proxyAddress`: `net.JoinHostPort`, so an IPv6 loopback (`::1`) becomes `[::1]:port`.
    pub fn proxy_address(&self) -> String {
        diting_go_compat::netaddr::join_host_port_text(&self.host, &self.port.to_string())
    }

    /// HTTP CONNECT has no datagram mode; only a direct or SOCKS5 route can carry UDP.
    pub fn supports_udp(&self) -> bool {
        !self.enabled || self.protocol == "socks5"
    }

    pub fn protocol(&self) -> &str {
        &self.protocol
    }

    pub fn uids(&self) -> &[i64] {
        &self.uids
    }
}

/// `OutboundProxyStatusCallback.onOutboundProxyStatus(String, String)`.
pub trait StatusSink: Send + Sync + 'static {
    fn status(&self, state: &str, message: &str);
}

/// The status callback plus the `(state, message)` dedupe Go kept on the proxy object.
#[derive(Default)]
pub struct StatusDispatcher {
    sink: RwLock<Option<Arc<dyn StatusSink>>>,
    last: Mutex<(String, String)>,
}

impl StatusDispatcher {
    pub fn set(&self, sink: Option<Arc<dyn StatusSink>>) {
        *self.sink.write().unwrap_or_else(|error| error.into_inner()) = sink;
    }

    pub fn report(&self, state: &str, message: &str) {
        {
            let mut last = self.last.lock().unwrap_or_else(|error| error.into_inner());
            if last.0 == state && last.1 == message {
                return;
            }
            *last = (state.to_string(), message.to_string());
        }
        let sink = self
            .sink
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        if let Some(sink) = sink {
            sink.status(state, message);
        }
    }
}

/// One engine's outbound state: the config, the protector and the status dispatcher.
#[derive(Clone)]
pub struct Outbound {
    inner: Arc<Inner>,
}

struct Inner {
    config: Config,
    protector: ProtectorHandle,
    status: Arc<StatusDispatcher>,
}

impl Outbound {
    /// The direct-only state a fresh engine starts in.
    pub fn direct(protector: ProtectorHandle) -> Self {
        Self::new(
            Config::default(),
            protector,
            Arc::new(StatusDispatcher::default()),
        )
    }

    pub fn new(config: Config, protector: ProtectorHandle, status: Arc<StatusDispatcher>) -> Self {
        Self {
            inner: Arc::new(Inner {
                config,
                protector,
                status,
            }),
        }
    }

    pub fn config(&self) -> &Config {
        &self.inner.config
    }

    pub fn route_for(&self, uid: i32) -> Route {
        self.inner.config.route_for(uid)
    }

    pub fn supports_udp(&self) -> bool {
        self.inner.config.supports_udp()
    }

    pub fn report(&self, state: &str, message: &str) {
        self.inner.status.report(state, message);
    }

    /// Dials `target` through `route`, reporting `ready`/`error` like `proxyFlowOutbound`.
    pub async fn dial_tcp(&self, route: Route, target: SocketAddr) -> Result<TcpStream, String> {
        if route == Route::Direct || !self.inner.config.enabled {
            return dial::connect_protected(target, &self.inner.protector, DIAL_TIMEOUT)
                .await
                .map_err(|error| format!("dial {target}: {error}"));
        }

        let proxy: SocketAddr = self.inner.config.proxy_address().parse().map_err(|_| {
            format!(
                "invalid proxy address {}",
                self.inner.config.proxy_address()
            )
        })?;
        let mut stream = dial::connect_protected(proxy, &self.inner.protector, DIAL_TIMEOUT)
            .await
            .map_err(|error| {
                let message = format!("connect outbound proxy: {error}");
                self.report("error", &message);
                message
            })?;
        let text = target.to_string();
        let result = match self.inner.config.protocol() {
            "socks5" => tokio::time::timeout(
                DIAL_TIMEOUT,
                handshake::socks5_connect(
                    &mut stream,
                    &self.inner.config.username,
                    &self.inner.config.password,
                    &text,
                ),
            )
            .await
            .unwrap_or_else(|_| Err("SOCKS5 connect: timed out".to_string())),
            _ => tokio::time::timeout(
                DIAL_TIMEOUT,
                handshake::http_connect(
                    &mut stream,
                    &self.inner.config.username,
                    &self.inner.config.password,
                    &text,
                ),
            )
            .await
            .unwrap_or_else(|_| Err("HTTP CONNECT response: timed out".to_string())),
        };
        match result {
            Ok(()) => {
                self.report("ready", "");
                Ok(stream)
            }
            Err(message) => {
                self.report("error", &message);
                Err(message)
            }
        }
    }

    /// Opens a connected datagram transport to `target`.
    pub async fn dial_udp(
        &self,
        route: Route,
        target: SocketAddr,
    ) -> Result<udp::UdpTransport, String> {
        if route == Route::Direct || !self.inner.config.enabled {
            return udp::UdpTransport::direct(target, &self.inner.protector).await;
        }
        if !self.inner.config.supports_udp() {
            return Err("outbound proxy does not support UDP".to_string());
        }
        let transport = udp::UdpTransport::socks5(
            target,
            self.inner.config.proxy_address(),
            self.inner.config.username.clone(),
            self.inner.config.password.clone(),
            &self.inner.protector,
        )
        .await;
        match &transport {
            Ok(_) => self.report("ready", ""),
            Err(message) => self.report("error", message),
        }
        transport
    }
}

impl std::fmt::Debug for Outbound {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Outbound")
            .field("enabled", &self.inner.config.enabled)
            .field("scope", &self.inner.config.scope)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blank_config_is_disabled() {
        let config = Config::parse("  ").expect("blank");
        assert!(!config.enabled());
        assert_eq!(config.route_for(10086), Route::Direct);
        assert!(config.supports_udp());
    }

    #[test]
    fn the_resolver_follows_the_proxy_only_for_the_all_scope() {
        let all = Config::parse(
            r#"{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080,"scope":"all"}"#,
        )
        .expect("all");
        assert!(all.resolver_uses_proxy());
        let apps = Config::parse(
            r#"{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080,"scope":"apps","uids":[1]}"#,
        )
        .expect("apps");
        assert!(!apps.resolver_uses_proxy(), "per-app keeps DNS direct");
        assert!(!Config::default().resolver_uses_proxy());
    }

    #[test]
    fn the_kernel_owns_the_validation_texts() {
        let error =
            Config::parse(r#"{"enabled":true,"protocol":"ftp","host":"127.0.0.1","port":1080}"#)
                .expect_err("bad protocol");
        assert_eq!(error, "unsupported outbound proxy protocol \"ftp\"");
        let error =
            Config::parse(r#"{"enabled":true,"protocol":"socks5","host":"8.8.8.8","port":1080}"#)
                .expect_err("non-loopback");
        assert!(error.contains("host must be 127.0.0.1 or ::1"), "{error}");
        let error = Config::parse("{\"enabled\":").expect_err("json");
        assert!(
            error.starts_with("invalid outbound proxy config: "),
            "{error}"
        );
    }

    #[test]
    fn the_scope_decides_per_uid() {
        let all = Config::parse(
            r#"{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080,"scope":"all"}"#,
        )
        .expect("all");
        assert_eq!(all.route_for(1000), Route::Proxy);
        assert_eq!(all.route_for(-1), Route::Proxy);

        let apps = Config::parse(
            r#"{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080,"scope":"apps","uids":[1000,1000,0,-5]}"#,
        )
        .expect("apps");
        assert_eq!(apps.uids(), &[1000]);
        assert_eq!(apps.route_for(1000), Route::Proxy);
        assert_eq!(apps.route_for(2000), Route::Direct);
        assert_eq!(
            apps.route_for(-1),
            Route::Direct,
            "an unknown owner stays direct"
        );
    }

    #[test]
    fn http_has_no_datagram_mode() {
        let config =
            Config::parse(r#"{"enabled":true,"protocol":"http","host":"127.0.0.1","port":8080}"#)
                .expect("http");
        assert!(!config.supports_udp());
    }

    #[test]
    fn an_ipv6_proxy_host_is_bracketed_for_the_dial() {
        let config =
            Config::parse(r#"{"enabled":true,"protocol":"socks5","host":"::1","port":1080}"#)
                .expect("v6 loopback");
        assert_eq!(config.proxy_address(), "[::1]:1080");
        let v4 =
            Config::parse(r#"{"enabled":true,"protocol":"socks5","host":"127.0.0.1","port":1080}"#)
                .expect("v4 loopback");
        assert_eq!(v4.proxy_address(), "127.0.0.1:1080");
    }

    #[test]
    fn status_events_are_deduplicated() {
        struct Recorder(Mutex<Vec<(String, String)>>);
        impl StatusSink for Recorder {
            fn status(&self, state: &str, message: &str) {
                self.0
                    .lock()
                    .expect("recorder")
                    .push((state.to_string(), message.to_string()));
            }
        }
        let dispatcher = StatusDispatcher::default();
        let recorder = Arc::new(Recorder(Mutex::new(Vec::new())));
        dispatcher.set(Some(recorder.clone()));
        dispatcher.report("connecting", "");
        dispatcher.report("connecting", "");
        dispatcher.report("error", "boom");
        assert_eq!(recorder.0.lock().expect("recorder").len(), 2);
    }
}

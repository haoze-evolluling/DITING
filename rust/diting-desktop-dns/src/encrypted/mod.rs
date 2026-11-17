//! Encrypted DNS entry points: DoT, DoH and DoQ.
//!
//! The encrypted transports are an additive capability: a listener that fails to bind (a busy
//! port, an unusable certificate) is logged and skipped, and the plain UDP/TCP service keeps
//! running. A query enters the same pipeline through
//! [`DnsServer::handle_with_identity`](crate::server::DnsServer::handle_with_identity); only the
//! transport and the identity hint differ.

pub mod client_id;
mod doh;
mod doq;
mod dot;
pub mod realip;

use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use diting_desktop_core::cert::CertManager;
use tokio::sync::watch;
use tokio::task::JoinHandle;

use crate::server::DnsServer;

pub use client_id::{client_id_from_path, client_id_from_server_name, normalize_doh_path};
pub use realip::{real_client_ip, ReverseProxyConfig};

/// Runtime configuration for the encrypted listeners.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EncryptedConfig {
    /// Host or wildcard address (`0.0.0.0`, `127.0.0.1`, `[::]`).
    pub listen_address: String,
    pub dot_enabled: bool,
    pub doh_enabled: bool,
    pub doq_enabled: bool,
    pub dot_port: u16,
    pub doh_port: u16,
    pub doq_port: u16,
    /// DoH request path; defaults to `/dns-query`.
    pub doh_path: String,
    /// The name clients are expected to use; the DoT/DoQ ClientID is a leading label of it.
    pub server_name: String,
    pub reverse_proxy: ReverseProxyConfig,
}

impl Default for EncryptedConfig {
    fn default() -> Self {
        Self {
            listen_address: "0.0.0.0".to_string(),
            dot_enabled: false,
            doh_enabled: false,
            doq_enabled: false,
            dot_port: 853,
            doh_port: 443,
            doq_port: 853,
            doh_path: "/dns-query".to_string(),
            server_name: "dns.lan".to_string(),
            reverse_proxy: ReverseProxyConfig::default(),
        }
    }
}

/// The running encrypted listeners.
pub struct EncryptedListeners {
    shutdown: watch::Sender<bool>,
    tasks: Mutex<Vec<JoinHandle<()>>>,
    doq_endpoint: Mutex<Option<quinn::Endpoint>>,
    addresses: Vec<String>,
    /// Per-transport bound addresses, so callers (DDR, the status endpoint) never have to guess
    /// which transport a positional entry in `addresses` belongs to.
    dot_address: Option<String>,
    doh_address: Option<String>,
    doq_address: Option<String>,
    enabled: AtomicBool,
}

impl EncryptedListeners {
    /// Binds and serves the requested transports.
    ///
    /// Individual bind/config failures are logged and skipped. `Err` is returned only when at
    /// least one listener was requested and every one of them failed.
    pub async fn start(
        server: Arc<DnsServer>,
        cert: Arc<CertManager>,
        config: EncryptedConfig,
    ) -> Result<Self, String> {
        let (shutdown, receiver) = watch::channel(false);
        let config = Arc::new(config);
        let mut tasks = Vec::new();
        let mut addresses = Vec::new();
        let mut dot_address = None;
        let mut doh_address = None;
        let mut doq_address = None;
        let mut doq_endpoint = None;
        let mut requested = 0usize;
        let mut started = 0usize;

        if config.dot_enabled {
            requested += 1;
            match dot::start(server.clone(), &cert, config.clone(), receiver.clone()).await {
                Ok((address, task)) => {
                    started += 1;
                    addresses.push(address.clone());
                    dot_address = Some(address);
                    tasks.push(task);
                }
                Err(error) => eprintln!("[加密DNS] DoT 监听器启动失败: {error}"),
            }
        }

        if config.doh_enabled {
            requested += 1;
            match doh::start(server.clone(), &cert, config.clone(), receiver.clone()).await {
                Ok((address, task)) => {
                    started += 1;
                    addresses.push(address.clone());
                    doh_address = Some(address);
                    tasks.push(task);
                }
                Err(error) => eprintln!("[加密DNS] DoH 监听器启动失败: {error}"),
            }
        }

        if config.doq_enabled {
            requested += 1;
            match doq::start(server.clone(), &cert, config.clone(), receiver.clone()).await {
                Ok((address, endpoint, task)) => {
                    started += 1;
                    addresses.push(address.clone());
                    doq_address = Some(address);
                    tasks.push(task);
                    doq_endpoint = Some(endpoint);
                }
                Err(error) => eprintln!("[加密DNS] DoQ 监听器启动失败: {error}"),
            }
        }

        if requested > 0 && started == 0 {
            return Err("所有加密 DNS 监听器均启动失败".to_string());
        }

        Ok(Self {
            shutdown,
            tasks: Mutex::new(tasks),
            doq_endpoint: Mutex::new(doq_endpoint),
            addresses,
            dot_address,
            doh_address,
            doq_address,
            enabled: AtomicBool::new(started > 0),
        })
    }

    /// Stops accepting, closes the QUIC endpoint, then aborts the accept loops after a short grace
    /// period so shutdown cannot hang on a stuck handshake.
    pub async fn shutdown(&self) {
        if !self.enabled.swap(false, Ordering::SeqCst) {
            return;
        }
        let _ = self.shutdown.send(true);
        if let Some(endpoint) = self.doq_endpoint.lock().unwrap().take() {
            endpoint.close(0u32.into(), b"shutdown");
        }

        tokio::time::sleep(Duration::from_millis(100)).await;
        let mut tasks = std::mem::take(&mut *self.tasks.lock().unwrap());
        for task in tasks.drain(..) {
            task.abort();
        }
        tokio::task::yield_now().await;
    }

    /// Whether at least one listener was bound at start time.
    pub fn enabled(&self) -> bool {
        self.enabled.load(Ordering::SeqCst)
    }

    /// The bound addresses, in DoT/DoH/DoQ order (the requested ones that succeeded).
    pub fn addresses(&self) -> Vec<String> {
        self.addresses.clone()
    }

    /// The address DoT is bound to, when that listener started.
    pub fn dot_address(&self) -> Option<&str> {
        self.dot_address.as_deref()
    }

    /// The address DoH is bound to, when that listener started.
    pub fn doh_address(&self) -> Option<&str> {
        self.doh_address.as_deref()
    }

    /// The address DoQ is bound to, when that listener started.
    pub fn doq_address(&self) -> Option<&str> {
        self.doq_address.as_deref()
    }
}

/// Builds `host:port`, expanding the empty host to the IPv4 wildcard.
///
/// An explicit `[::]` stays IPv6; a bare IPv6 literal is bracketed so it remains a valid socket
/// address. Port `0` is intentionally preserved for ephemeral binds.
pub(crate) fn socket_address(host: &str, port: u16) -> Result<String, String> {
    let host = host.trim();
    let host = if host.is_empty() { "0.0.0.0" } else { host };
    let bare = host.trim_start_matches('[').trim_end_matches(']');
    let ip = bare
        .parse::<IpAddr>()
        .map_err(|error| format!("监听地址 {host} 不是合法 IP: {error}"))?;
    Ok(SocketAddr::new(ip, port).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_expand_wildcards_and_bracket_ipv6() {
        assert_eq!(socket_address("", 853).unwrap(), "0.0.0.0:853");
        assert_eq!(socket_address("127.0.0.1", 0).unwrap(), "127.0.0.1:0");
        assert_eq!(socket_address("[::]", 853).unwrap(), "[::]:853");
        assert_eq!(socket_address("::1", 853).unwrap(), "[::1]:853");
        assert!(socket_address("localhost", 853).is_err());
    }

    #[test]
    fn default_path_and_ports_are_the_rfc_defaults() {
        let config = EncryptedConfig::default();
        assert_eq!(config.doh_path, "/dns-query");
        assert_eq!(config.dot_port, 853);
        assert_eq!(config.doh_port, 443);
        assert_eq!(config.doq_port, 853);
        assert!(!config.reverse_proxy.enabled);
    }
}

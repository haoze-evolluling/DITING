pub mod background;
pub mod cache;
pub mod clients;
pub mod dns;
pub mod encrypted;
pub mod filter;
pub mod querylog;
pub mod rewrite_zone;
pub mod safebrowsing;
pub mod safesearch;
pub mod security;
pub mod status;
pub mod upstream;
pub mod web;

use std::fmt;
use std::net::SocketAddr;

use diting_desktop_api::config::{Config, DNSConfig};
use diting_desktop_api::platform_types::PortCheckResult;
use diting_desktop_dns::context::Transport;

#[derive(Debug, Clone)]
pub struct ControllerError {
    pub message: String,
    pub conflict: Option<PortCheckResult>,
}

impl ControllerError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            conflict: None,
        }
    }

    pub fn conflict(result: PortCheckResult) -> Self {
        let message = if result.diagnostic.is_empty() {
            "53 端口已被占用，无法启动 DNS 监听器".to_string()
        } else {
            format!("53 端口已被占用: {}", result.diagnostic)
        };
        Self {
            message,
            conflict: Some(result),
        }
    }
}

impl fmt::Display for ControllerError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ControllerError {}

impl From<String> for ControllerError {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

impl From<&str> for ControllerError {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

pub fn effective_listen_addresses(config: &DNSConfig) -> (Vec<String>, Vec<String>) {
    let port = config
        .udp_addresses
        .iter()
        .chain(config.tcp_addresses.iter())
        .find_map(|address| {
            address
                .rsplit_once(':')
                .and_then(|(_, port)| port.parse::<u16>().ok())
        })
        .filter(|port| *port > 0)
        .unwrap_or(53);

    if config.allow_lan {
        let addresses = vec![format!("0.0.0.0:{port}"), format!("[::]:{port}")];
        return (addresses.clone(), addresses);
    }

    let local = |addresses: &[String]| -> Vec<String> {
        addresses
            .iter()
            .map(|address| match address.rsplit_once(':') {
                Some((host, _)) if host.starts_with('[') || !host.contains(':') => match host {
                    "0.0.0.0" => format!("127.0.0.1:{port}"),
                    "[::]" | "::" => format!("[::1]:{port}"),
                    _ => address.clone(),
                },
                _ => address.clone(),
            })
            .collect()
    };
    (local(&config.udp_addresses), local(&config.tcp_addresses))
}

pub fn error_message(result: Result<(), ControllerError>) -> Option<ControllerError> {
    result.err()
}

pub fn client_host(remote: SocketAddr) -> String {
    remote.ip().to_string()
}

pub fn transport_name(transport: Transport) -> &'static str {
    transport.as_str()
}

pub fn config_snapshot(runtime: &crate::AppRuntime) -> Config {
    runtime.config()
}

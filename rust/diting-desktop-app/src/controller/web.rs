//! LAN DNS exposure and the remote Web console (`/dns/lan*`, `/web/*`).

use serde::{Deserialize, Serialize};

use crate::controller::{effective_listen_addresses, ControllerError};
use crate::AppRuntime;

/// `ipc.LANStatusResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LanStatusResponse {
    #[serde(rename = "allowLAN")]
    pub allow_lan: bool,
    pub listen_addresses: Vec<String>,
    pub lan_addresses: Vec<String>,
    pub firewall_allowed: bool,
    pub firewall_backend: String,
}

/// `ipc.ConfigureLANRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureLANRequest {
    #[serde(default, rename = "allowLAN")]
    pub allow_lan: bool,
    #[serde(default)]
    pub configure_firewall: bool,
}

/// `ipc.ConfigureFirewallRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureFirewallRequest {
    #[serde(default)]
    pub enable: bool,
}

/// `ipc.WebStatusResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WebStatusResponse {
    pub enabled: bool,
    pub port: i32,
    pub listen_address: String,
    pub lan_addresses: Vec<String>,
    pub web_urls: Vec<String>,
    pub firewall_allowed: bool,
    pub firewall_backend: String,
    pub initialized: bool,
    pub username: String,
}

/// `ipc.ConfigureWebRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureWebRequest {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub port: i32,
    #[serde(default)]
    pub configure_firewall: bool,
}

fn firewall_backend(runtime: &AppRuntime) -> String {
    runtime
        .platform()
        .map(|platform| platform.firewall_backend.clone())
        .unwrap_or_else(|| "none".to_string())
}

fn effective_web_port(runtime: &AppRuntime) -> i32 {
    let config = runtime.config();
    if config.web.listen_port > 0 {
        return config.web.listen_port;
    }
    if let Ok(address) = config.ipc.listen_address.parse::<std::net::SocketAddr>() {
        return i32::from(address.port());
    }
    config
        .ipc
        .listen_address
        .rsplit_once(':')
        .and_then(|(_, port)| port.parse().ok())
        .unwrap_or(15353)
}

impl AppRuntime {
    /// `GetLANStatus`.
    pub async fn lan_status(&self) -> LanStatusResponse {
        let config = self.config();
        let (udp, _) = effective_listen_addresses(&config.dns);
        let firewall_allowed = match self
            .platform()
            .and_then(|platform| platform.firewall.clone())
        {
            Some(firewall) => firewall.check_port53().await.unwrap_or(false),
            None => false,
        };
        LanStatusResponse {
            allow_lan: config.dns.allow_lan,
            listen_addresses: udp,
            lan_addresses: self.lan_addresses(),
            firewall_allowed,
            firewall_backend: firewall_backend(self),
        }
    }

    /// `ConfigureLAN`; restarts a running listener so the new binding applies immediately.
    pub async fn configure_lan(&self, request: ConfigureLANRequest) -> Result<(), ControllerError> {
        let was_running = self.is_dns_running();
        self.update_config(|config| {
            config.dns.allow_lan = request.allow_lan;
            let (udp, tcp) = effective_listen_addresses(&config.dns);
            config.dns.udp_addresses = udp;
            config.dns.tcp_addresses = tcp;
        })
        .map_err(ControllerError::new)?;

        if request.configure_firewall && firewall_backend(self) != "none" {
            if let Some(firewall) = self
                .platform()
                .and_then(|platform| platform.firewall.clone())
            {
                let _ = firewall.configure_port53(request.allow_lan).await;
            }
        }

        if was_running {
            let takeover = self
                .platform()
                .and_then(|platform| platform.dns_manager.clone())
                .map(|manager| manager.is_takeover_active())
                .unwrap_or(false);
            self.stop_dns_checked().await?;
            self.start_dns_checked().await?;
            if takeover {
                let _ = self.enable_takeover().await;
            }
        }
        Ok(())
    }

    /// `ConfigureFirewall`.
    pub async fn configure_firewall(&self, enable: bool) -> Result<(), ControllerError> {
        let firewall = self
            .platform()
            .and_then(|platform| platform.firewall.clone())
            .ok_or_else(|| ControllerError::new("防火墙管理器未初始化"))?;
        firewall
            .configure_port53(enable)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    /// `GetWebStatus`. Authentication state is supplied by the IPC-owned auth manager.
    pub async fn web_status(&self, initialized: bool, username: &str) -> WebStatusResponse {
        let config = self.config();
        let port = effective_web_port(self);
        let lan_addresses = self.lan_addresses();
        let mut web_urls: Vec<String> = lan_addresses
            .iter()
            .map(|ip| {
                if ip.contains(':') {
                    format!("http://[{ip}]:{port}")
                } else {
                    format!("http://{ip}:{port}")
                }
            })
            .collect();
        if web_urls.is_empty() {
            web_urls.push(format!("http://127.0.0.1:{port}"));
        }
        let firewall_allowed = match self
            .platform()
            .and_then(|platform| platform.firewall.clone())
        {
            Some(firewall) => firewall.check_web().await.unwrap_or(false),
            None => false,
        };
        WebStatusResponse {
            enabled: config.web.enabled,
            port,
            listen_address: config.ipc.listen_address,
            lan_addresses,
            web_urls,
            firewall_allowed,
            firewall_backend: firewall_backend(self),
            initialized,
            username: username.to_string(),
        }
    }

    /// `ConfigureWeb`.
    ///
    /// The listen address is persisted; applying it to the already-running IPC socket requires a
    /// restart, which the service performs on the next start (the Go server did an in-process
    /// rebind, which the Rust supervisor does not attempt from inside a request handler).
    pub async fn configure_web(&self, request: ConfigureWebRequest) -> Result<(), ControllerError> {
        let port = if request.port > 0 {
            request.port
        } else {
            effective_web_port(self)
        };
        let listen = if request.enabled {
            format!("0.0.0.0:{port}")
        } else {
            format!("127.0.0.1:{port}")
        };
        self.update_config(|config| {
            config.web.enabled = request.enabled;
            config.web.listen_port = port;
            config.ipc.listen_address = listen;
        })
        .map_err(ControllerError::new)?;

        if request.configure_firewall && firewall_backend(self) != "none" {
            if let Some(firewall) = self
                .platform()
                .and_then(|platform| platform.firewall.clone())
            {
                let _ = firewall.configure_web(port, request.enabled).await;
            }
        }
        Ok(())
    }

    /// `ConfigureWebFirewall`.
    pub async fn configure_web_firewall(&self, enable: bool) -> Result<(), ControllerError> {
        let firewall = self
            .platform()
            .and_then(|platform| platform.firewall.clone())
            .ok_or_else(|| ControllerError::new("防火墙管理器未初始化"))?;
        firewall
            .configure_web(effective_web_port(self), enable)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    pub fn web_port(&self) -> i32 {
        effective_web_port(self)
    }
}

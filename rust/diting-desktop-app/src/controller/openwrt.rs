use serde::{Deserialize, Serialize};

use diting_desktop_api::config::{paths as config_paths, Config, OpenWrtConfig};

use crate::controller::{effective_listen_addresses, ControllerError};
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenWrtStatusResponse {
    pub supported: bool,
    pub distro: String,
    pub active: bool,
    pub dns_running: bool,
    pub mode: String,
    pub dnsmasq_port: u16,
    pub upstream_port: u16,
    pub forward_local_domain: bool,
    pub local_domain: String,
    pub force_redirect_53: bool,
    pub redirect_active: bool,
    pub desired_active: bool,
    pub firewall_backend: String,
    pub listen_addresses: Vec<String>,
    pub persistent_dir: String,
    pub volatile_dir: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureOpenWrtRequest {
    pub mode: Option<String>,
    pub dnsmasq_port: Option<u16>,
    pub upstream_port: Option<u16>,
    pub forward_local_domain: Option<bool>,
    pub force_redirect_53: Option<bool>,
}

pub fn openwrt_listen_addresses(config: &Config) -> (Vec<String>, Vec<String>) {
    if !config.openwrt.is_replace_mode() {
        let port = config.openwrt.upstream_port;
        let addrs = vec![format!("127.0.0.1:{port}"), format!("[::1]:{port}")];
        return (addrs.clone(), addrs);
    }
    if config.dns.allow_lan {
        let addrs = vec!["0.0.0.0:53".to_string(), "[::]:53".to_string()];
        (addrs.clone(), addrs)
    } else {
        let addrs = vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()];
        (addrs.clone(), addrs)
    }
}

impl AppRuntime {
    pub fn is_openwrt_platform(&self) -> bool {
        self.platform()
            .is_some_and(|platform| platform.platform_kind == "openwrt")
            || config_paths::is_openwrt()
    }

    pub fn platform_kind(&self) -> String {
        if let Some(platform) = self.platform() {
            if !platform.platform_kind.is_empty() {
                return platform.platform_kind.clone();
            }
        }
        if config_paths::is_openwrt() {
            "openwrt".to_string()
        } else {
            self.platform_name()
        }
    }

    pub fn distro_name(&self) -> Option<String> {
        self.platform()
            .and_then(|platform| {
                (!platform.distro_name.is_empty()).then(|| platform.distro_name.clone())
            })
            .or_else(config_paths::openwrt_distro_name)
    }

    /// OpenWrt 专属启动序列：
    /// - 替换模式下必须先通过 UCI 将 dnsmasq 迁至辅端口释放 53，再绑定 53 监听；监听失败立即回滚 dnsmasq。
    /// - 上游模式下先绑定独立本地端口，再通过 UCI 将 dnsmasq 指向该端口；UCI 失败则停止监听。
    pub async fn start_openwrt_dns_and_takeover(&self) -> Result<(), ControllerError> {
        let platform = self
            .platform()
            .ok_or_else(|| ControllerError::new("OpenWrt 平台能力未初始化"))?;
        let manager = platform
            .dns_manager
            .clone()
            .ok_or_else(|| ControllerError::new("OpenWrt DNS 管理器未初始化"))?;

        let updated = self
            .update_config(|cfg| {
                cfg.openwrt.normalize();
                cfg.openwrt.desired_active = true;
                let (udp, tcp) = openwrt_listen_addresses(cfg);
                cfg.dns.udp_addresses = udp;
                cfg.dns.tcp_addresses = tcp;
            })
            .map_err(ControllerError::new)?;

        if let Some(openwrt) = &platform.openwrt {
            openwrt.sync_config(updated.openwrt.clone());
        }

        if updated.openwrt.is_replace_mode() {
            manager
                .takeover(&[])
                .await
                .map_err(|error| ControllerError::new(format!("迁移 dnsmasq 端口失败: {error}")))?;
            self.refresh_resolver(&self.config());
            if let Err(error) = self.start_dns().await {
                let _ = manager.restore().await;
                return Err(ControllerError::new(format!(
                    "启动 53 端口 DNS 监听器失败（已自动回滚 dnsmasq）: {error}"
                )));
            }
        } else {
            self.refresh_resolver(&self.config());
            self.start_dns()
                .await
                .map_err(|error| ControllerError::new(format!("启动本地转发端口失败: {error}")))?;
            if let Err(error) = manager.takeover(&[]).await {
                self.stop_dns().await;
                return Err(ControllerError::new(format!(
                    "配置 dnsmasq 上游转发失败: {error}"
                )));
            }
        }
        Ok(())
    }

    pub async fn stop_openwrt_dns_and_takeover(
        &self,
        clear_desired: bool,
    ) -> Result<(), ControllerError> {
        if clear_desired {
            let _ = self.update_config(|cfg| {
                cfg.openwrt.desired_active = false;
            });
        }
        self.stop_dns().await;
        if let Some(manager) = self.platform().and_then(|p| p.dns_manager.clone()) {
            manager
                .restore()
                .await
                .map_err(|error| ControllerError::new(error.to_string()))?;
        }
        Ok(())
    }

    pub async fn openwrt_status(&self) -> OpenWrtStatusResponse {
        let config = self.config();
        let platform = self.platform();
        let openwrt = platform.as_ref().and_then(|p| p.openwrt.clone());
        let supported = openwrt.is_some() || config_paths::is_openwrt();
        let distro = openwrt
            .as_ref()
            .map(|ow| ow.distro_name())
            .or_else(config_paths::openwrt_distro_name)
            .unwrap_or_default();
        let active = platform
            .as_ref()
            .and_then(|p| p.dns_manager.as_ref())
            .is_some_and(|m| m.is_takeover_active());
        let local_domain = match &openwrt {
            Some(ow) => ow.probe_local_domain().await,
            None => "lan".to_string(),
        };
        let redirect_active = match &openwrt {
            Some(ow) => ow.check_dns_redirect().await,
            None => false,
        };
        let firewall_backend = platform
            .as_ref()
            .map(|p| p.firewall_backend.clone())
            .unwrap_or_else(|| "none".to_string());
        let listen_addresses = if supported {
            openwrt_listen_addresses(&config).0
        } else {
            effective_listen_addresses(&config.dns).0
        };

        OpenWrtStatusResponse {
            supported,
            distro,
            active,
            dns_running: self.is_dns_running(),
            mode: config.openwrt.mode.clone(),
            dnsmasq_port: config.openwrt.dnsmasq_port,
            upstream_port: config.openwrt.upstream_port,
            forward_local_domain: config.openwrt.forward_local_domain,
            local_domain,
            force_redirect_53: config.openwrt.force_redirect_53,
            redirect_active,
            desired_active: config.openwrt.desired_active,
            firewall_backend,
            listen_addresses,
            persistent_dir: config_paths::OPENWRT_PERSISTENT_DIR.to_string(),
            volatile_dir: config_paths::OPENWRT_VOLATILE_DIR.to_string(),
        }
    }

    pub async fn configure_openwrt(
        &self,
        request: ConfigureOpenWrtRequest,
    ) -> Result<OpenWrtStatusResponse, ControllerError> {
        let was_active = self.is_dns_running()
            || self
                .platform()
                .and_then(|p| p.dns_manager.clone())
                .is_some_and(|m| m.is_takeover_active());

        let updated = self
            .update_config(|cfg| {
                apply_openwrt_patch(&mut cfg.openwrt, &request);
                cfg.openwrt.normalize();
                if config_paths::is_openwrt() || was_active {
                    let (udp, tcp) = openwrt_listen_addresses(cfg);
                    cfg.dns.udp_addresses = udp;
                    cfg.dns.tcp_addresses = tcp;
                }
            })
            .map_err(ControllerError::new)?;

        if let Some(openwrt) = self.platform().and_then(|p| p.openwrt.clone()) {
            openwrt.sync_config(updated.openwrt.clone());
            if !was_active && request.force_redirect_53 == Some(false) {
                let _ = openwrt.configure_dns_redirect(false, 53).await;
            }
        }

        if was_active {
            self.stop_dns().await;
            self.start_openwrt_dns_and_takeover().await?;
        }
        Ok(self.openwrt_status().await)
    }
}

fn apply_openwrt_patch(target: &mut OpenWrtConfig, patch: &ConfigureOpenWrtRequest) {
    if let Some(mode) = &patch.mode {
        target.mode = mode.clone();
    }
    if let Some(port) = patch.dnsmasq_port {
        target.dnsmasq_port = port;
    }
    if let Some(port) = patch.upstream_port {
        target.upstream_port = port;
    }
    if let Some(forward) = patch.forward_local_domain {
        target.forward_local_domain = forward;
    }
    if let Some(redirect) = patch.force_redirect_53 {
        target.force_redirect_53 = redirect;
    }
}

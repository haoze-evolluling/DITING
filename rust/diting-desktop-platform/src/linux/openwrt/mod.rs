pub mod detect;
pub mod dhcp_leases;
pub mod dns_manager;
pub mod firewall;
pub mod portcheck;
pub mod service;
pub mod uci;

#[cfg(test)]
mod tests;

use std::net::IpAddr;
use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::config::OpenWrtConfig;

use crate::error::PlatformResult;
use crate::netutil::is_private_ipv4;
use crate::traits::{ClientHostLookup, OpenWrtPlatform};

use super::adapter::list_managed_interfaces;

pub use detect::{detect_firewall_gen, distro_description, is_openwrt, FirewallGen};
pub use dhcp_leases::DhcpLeaseTable;
pub use dns_manager::{DnsmasqBackup, OpenWrtAdapterScanner, OpenWrtDnsManager};
pub use firewall::OpenWrtFirewall;
pub use portcheck::OpenWrtPortChecker;
pub use service::{OpenWrtAutoStart, OpenWrtServiceManager};

pub const PLATFORM_DISPLAY_NAME: &str = "OpenWrt";
pub const SERVICE_NAME: &str = "diting";
pub const INIT_SCRIPT_PATH: &str = "/etc/init.d/diting";
pub const PORT_CHECK_HINT: &str = "是否检测到 OpenWrt dnsmasq 占用";

pub struct OpenWrtBridge {
    dns_manager: Arc<OpenWrtDnsManager>,
    firewall: Arc<OpenWrtFirewall>,
    leases: Arc<DhcpLeaseTable>,
}

impl OpenWrtBridge {
    pub fn new(
        dns_manager: Arc<OpenWrtDnsManager>,
        firewall: Arc<OpenWrtFirewall>,
        leases: Arc<DhcpLeaseTable>,
    ) -> Self {
        Self {
            dns_manager,
            firewall,
            leases,
        }
    }
}

#[async_trait]
impl OpenWrtPlatform for OpenWrtBridge {
    fn distro_name(&self) -> String {
        distro_description()
    }

    fn detected_local_domain(&self) -> String {
        self.dns_manager.detected_local_domain()
    }

    async fn probe_local_domain(&self) -> String {
        self.dns_manager.probe_local_domain().await
    }

    fn sync_config(&self, config: OpenWrtConfig) {
        self.dns_manager.set_openwrt_config(config);
    }

    async fn check_dns_redirect(&self) -> bool {
        self.firewall.check_dns_redirect().await
    }

    async fn configure_dns_redirect(&self, enable: bool, target_port: u16) -> PlatformResult<()> {
        self.firewall
            .configure_dns_redirect(enable, target_port)
            .await
    }

    fn client_name_lookup(&self) -> Option<ClientHostLookup> {
        let table = Arc::clone(&self.leases);
        Some(Arc::new(move |ip| table.lookup(ip)))
    }
}

/// 提取 OpenWrt 局域网地址：优先提取 `br-lan` 与 `lan*` 桥接/物理接口上的私网 IPv4，
/// 排除 PPPoE 拨号、VPN 隧道及 Docker 容器桥接接口。
pub fn lan_addresses() -> PlatformResult<Vec<String>> {
    let interfaces = list_managed_interfaces()?;
    let mut br_lan_v4 = Vec::new();
    let mut other_private_v4 = Vec::new();
    let mut lan_v6 = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for iface in interfaces {
        if !iface.is_up() || iface.is_loopback() || iface.has_point_to_point() {
            continue;
        }
        if is_excluded_router_iface(&iface.name) {
            continue;
        }
        let is_primary_lan = iface.name == "br-lan" || iface.name.starts_with("lan");
        for addr in iface.addresses {
            let text = addr.to_string();
            if !seen.insert(text.clone()) {
                continue;
            }
            match addr {
                IpAddr::V4(v4) => {
                    if v4.is_loopback()
                        || v4.is_unspecified()
                        || v4.is_link_local()
                        || v4.is_multicast()
                        || v4.is_broadcast()
                    {
                        continue;
                    }
                    if is_primary_lan && is_private_ipv4(v4) {
                        br_lan_v4.push(text);
                    } else if is_private_ipv4(v4) {
                        other_private_v4.push(text);
                    }
                }
                IpAddr::V6(v6) => {
                    if v6.is_loopback()
                        || v6.is_unspecified()
                        || v6.is_multicast()
                        || v6.is_unicast_link_local()
                    {
                        continue;
                    }
                    if is_primary_lan {
                        lan_v6.push(text);
                    }
                }
            }
        }
    }

    let mut out = br_lan_v4;
    out.extend(other_private_v4);
    out.extend(lan_v6);
    Ok(out)
}

fn is_excluded_router_iface(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.starts_with("pppoe")
        || lower.starts_with("wan")
        || lower.starts_with("docker")
        || lower.starts_with("veth")
        || lower.starts_with("tun")
        || lower.starts_with("tap")
        || lower.starts_with("wg")
        || lower.starts_with("utun")
        || lower.starts_with("tailscale")
        || lower.starts_with("zt")
}

#![cfg(unix)]
//! Linux platform backend, ported from the former Go service's `internal/platform/linux`.
//!
//! The implementations shell out to `resolvectl`, `nmcli`, `systemctl`, firewall tools and parse
//! `/proc`; shared value types and the capability traits live in the crate root.

pub mod adapter;
pub mod autostart;
pub mod backend;
pub mod dnsstate;
pub mod firewall;
pub mod portcheck;
pub mod restore_script;
pub mod service;
pub mod takeover;

mod files;

use std::sync::Arc;

use async_trait::async_trait;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::{CommandExecutor, SystemExecutor};
use crate::netutil::{self, InterfaceAddress};
use crate::traits::PrivilegedExecutor;

pub use adapter::LinuxAdapterScanner;
pub use autostart::LinuxAutoStart;
pub use firewall::LinuxFirewall;
pub use portcheck::LinuxPortChecker;
pub use service::LinuxServiceManager;
pub use takeover::LinuxDnsManager;

pub const PLATFORM_DISPLAY_NAME: &str = "Linux";
pub const SERVICE_NAME: &str = "diting-dnsservice";
pub const SERVICE_DISPLAY_NAME: &str = "谛听 DNS 内核特权服务";
pub const SERVICE_DESCRIPTION: &str =
    "谛听 Linux 端 DNS 内核特权服务，负责系统 DNS 接管与多协议上游转发。";
pub const PORT_CHECK_HINT: &str = "是否检测到 systemd-resolved stub";

/// Every address currently assigned to a network interface, in interface-index order.
pub fn interface_addresses() -> PlatformResult<Vec<InterfaceAddress>> {
    let interfaces = adapter::list_managed_interfaces()?;
    let mut addresses = Vec::new();
    for interface in interfaces {
        for address in interface.addresses {
            addresses.push(InterfaceAddress {
                interface: interface.name.clone(),
                address,
            });
        }
    }
    Ok(addresses)
}

/// Active, non-virtual, non-loopback LAN addresses, private IPv4 first.
pub fn lan_addresses() -> PlatformResult<Vec<String>> {
    // Go's `GetLANAddresses` ignores down, loopback and point-to-point interfaces before applying
    // the virtual-name filter; `InterfaceAddress` alone cannot carry those flags.
    let interfaces = adapter::list_managed_interfaces()?;
    let mut addresses = Vec::new();
    for interface in interfaces {
        if !interface.is_up() || interface.is_loopback() || interface.has_point_to_point() {
            continue;
        }
        for address in interface.addresses {
            addresses.push(InterfaceAddress {
                interface: interface.name.clone(),
                address,
            });
        }
    }
    Ok(netutil::extract_lan_addresses(&addresses))
}

/// `"firewalld" | "ufw" | "nftables" | "iptables" | "none"`.
pub fn firewall_backend_name() -> String {
    firewall::detect_firewall_manager().as_str().to_string()
}

/// Linux has no on-demand elevation; this runs the program as the current user and refuses when
/// the process is not root, matching the Go `DefaultPrivilegedExecutor`.
pub fn new_privileged_executor() -> Arc<dyn PrivilegedExecutor> {
    Arc::new(LinuxPrivilegedExecutor)
}

struct LinuxPrivilegedExecutor;

#[async_trait]
impl PrivilegedExecutor for LinuxPrivilegedExecutor {
    async fn run_elevated(&self, exe: &str, args: &[String]) -> PlatformResult<()> {
        if !crate::privilege::is_elevated() {
            return Err(PlatformError::message(
                "当前权限不足，请以 root 身份重新运行（例如 sudo diting-service）",
            ));
        }
        let args: Vec<&str> = args.iter().map(String::as_str).collect();
        SystemExecutor::new().run(exe, &args).await?;
        Ok(())
    }

    fn is_elevated(&self) -> bool {
        crate::privilege::is_elevated()
    }
}

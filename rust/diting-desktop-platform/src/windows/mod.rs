//! Windows platform backend.
//!
//! Every capability the desktop service needs is implemented here with native Win32 calls where
//! possible and `netsh`/`sc` as a fallback. The shared DTOs and traits live in
//! `diting-desktop-api` and `crate::traits`.

pub mod adapter;
pub mod autostart;
pub mod dns_native;
pub mod elevate;
pub mod firewall;
pub mod portcheck;
pub mod restore_script;
pub mod service;
pub mod takeover;

mod adapter_native;
mod adapter_registry;
mod portcheck_ics;
mod portcheck_native;
mod service_scm;

pub use adapter::WindowsAdapterScanner;
pub use autostart::WindowsAutoStart;
pub use elevate::WindowsPrivilegedExecutor;
pub use firewall::WindowsFirewall;
pub use portcheck::WindowsPortChecker;
pub use service::WindowsServiceManager;
pub use takeover::WindowsDnsManager;

use crate::error::PlatformResult;

/// Firewall backend identifier reported to the UI.
pub const FIREWALL_BACKEND_NAME: &str = "windows";
/// Human-readable platform name.
pub const PLATFORM_DISPLAY_NAME: &str = "Windows";
/// Privileged core service name.
pub const SERVICE_NAME: &str = "DitingDNSService";
/// Service display name shown by `services.msc`.
pub const SERVICE_DISPLAY_NAME: &str = "谛听 DNS 内核特权服务";
/// Service description written by the installer.
pub const SERVICE_DESCRIPTION: &str =
    "谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。";
/// Diagnostic hint shown when port 53 is blocked.
pub const PORT_CHECK_HINT: &str = "是否检测到 ICS (SharedAccess)";

/// Unicast addresses of operational interfaces, used by the LAN address endpoint.
pub fn interface_addresses() -> PlatformResult<Vec<crate::netutil::InterfaceAddress>> {
    adapter_native::native_interface_addresses()
}

/// LAN-reachable addresses, private IPv4 first, matching `platform.GetLANAddresses`.
pub fn lan_addresses() -> PlatformResult<Vec<String>> {
    let interfaces = interface_addresses()?;
    Ok(crate::netutil::extract_lan_addresses(&interfaces))
}

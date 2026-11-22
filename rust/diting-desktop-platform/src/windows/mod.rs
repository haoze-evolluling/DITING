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

pub const FIREWALL_BACKEND_NAME: &str = "windows";
pub const PLATFORM_DISPLAY_NAME: &str = "Windows";
pub const SERVICE_NAME: &str = "DitingDNSService";
pub const SERVICE_DISPLAY_NAME: &str = "谛听 DNS 内核特权服务";
pub const SERVICE_DESCRIPTION: &str =
    "谛听 Windows 端 DNS 内核特权服务，负责双栈物理网卡 DNS 接管与多协议上游转发。";
pub const PORT_CHECK_HINT: &str = "是否检测到 ICS (SharedAccess)";

pub fn interface_addresses() -> PlatformResult<Vec<crate::netutil::InterfaceAddress>> {
    adapter_native::native_interface_addresses()
}

pub fn lan_addresses() -> PlatformResult<Vec<String>> {
    let interfaces = interface_addresses()?;
    Ok(crate::netutil::extract_lan_addresses(&interfaces))
}

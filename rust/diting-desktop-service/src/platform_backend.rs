use std::sync::Arc;

use diting_desktop_api::config::OpenWrtConfig;
use diting_desktop_app::PlatformHandles;
use diting_desktop_platform::error::PlatformResult;
use diting_desktop_platform::exec::{CommandExecutor, SystemExecutor};
use diting_desktop_platform::traits::{
    AdapterScanner, AutoStartManager, DnsManager, FirewallManager, OpenWrtPlatform, PortChecker,
    ServiceManager, StateStore,
};

pub fn executor() -> Arc<dyn CommandExecutor> {
    Arc::new(SystemExecutor::new())
}

pub fn is_elevated() -> bool {
    diting_desktop_platform::privilege::is_elevated()
}

pub fn is_openwrt() -> bool {
    #[cfg(unix)]
    {
        diting_desktop_platform::linux::openwrt::is_openwrt()
    }
    #[cfg(not(unix))]
    {
        false
    }
}

pub fn lan_addresses() -> PlatformResult<Vec<String>> {
    #[cfg(windows)]
    {
        diting_desktop_platform::windows::lan_addresses()
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return diting_desktop_platform::linux::openwrt::lan_addresses();
        }
        diting_desktop_platform::linux::lan_addresses()
    }
}

pub fn platform_name() -> &'static str {
    #[cfg(windows)]
    {
        diting_desktop_platform::windows::PLATFORM_DISPLAY_NAME
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return diting_desktop_platform::linux::openwrt::PLATFORM_DISPLAY_NAME;
        }
        diting_desktop_platform::linux::PLATFORM_DISPLAY_NAME
    }
}

pub fn platform_kind() -> String {
    if is_openwrt() {
        "openwrt".to_string()
    } else {
        std::env::consts::OS.to_string()
    }
}

pub fn distro_name() -> String {
    #[cfg(unix)]
    {
        if is_openwrt() {
            return diting_desktop_platform::linux::openwrt::distro_description();
        }
    }
    String::new()
}

pub fn port_check_hint() -> &'static str {
    #[cfg(windows)]
    {
        diting_desktop_platform::windows::PORT_CHECK_HINT
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return diting_desktop_platform::linux::openwrt::PORT_CHECK_HINT;
        }
        diting_desktop_platform::linux::PORT_CHECK_HINT
    }
}

pub fn dns_manager(
    store: Arc<dyn StateStore>,
    openwrt_cfg: &OpenWrtConfig,
    version: &str,
) -> (Arc<dyn DnsManager>, Option<Arc<dyn OpenWrtPlatform>>) {
    #[cfg(windows)]
    {
        let _ = openwrt_cfg;
        (
            Arc::new(diting_desktop_platform::windows::WindowsDnsManager::new(
                executor(),
                store,
                version,
            )),
            None,
        )
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            use diting_desktop_platform::linux::openwrt::{
                DhcpLeaseTable, OpenWrtBridge, OpenWrtDnsManager, OpenWrtFirewall,
            };
            let exec = executor();
            let fw = Arc::new(OpenWrtFirewall::new(Arc::clone(&exec)));
            let mgr = Arc::new(OpenWrtDnsManager::new(
                exec,
                store,
                Arc::clone(&fw),
                openwrt_cfg.clone(),
                version,
            ));
            let bridge = Arc::new(OpenWrtBridge::new(
                Arc::clone(&mgr),
                fw,
                Arc::new(DhcpLeaseTable::new()),
            ));
            return (mgr, Some(bridge));
        }
        (
            Arc::new(diting_desktop_platform::linux::LinuxDnsManager::new(
                executor(),
                store,
                version,
            )),
            None,
        )
    }
}

pub fn adapter_scanner() -> Arc<dyn AdapterScanner> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsAdapterScanner::new(executor()))
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return Arc::new(diting_desktop_platform::linux::openwrt::OpenWrtAdapterScanner::new());
        }
        Arc::new(diting_desktop_platform::linux::LinuxAdapterScanner::new(
            executor(),
        ))
    }
}

pub fn port_checker(dns_manager: Option<Arc<dyn DnsManager>>) -> Arc<dyn PortChecker> {
    #[cfg(windows)]
    {
        let _ = dns_manager;
        Arc::new(diting_desktop_platform::windows::WindowsPortChecker::new(
            executor(),
        ))
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            if let Some(mgr) = dns_manager {
                return Arc::new(
                    diting_desktop_platform::linux::openwrt::OpenWrtPortChecker::new(mgr),
                );
            }
        }
        Arc::new(diting_desktop_platform::linux::LinuxPortChecker::new(
            executor(),
        ))
    }
}

pub fn service_manager() -> Arc<dyn ServiceManager> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsServiceManager::new(executor(), None))
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return Arc::new(
                diting_desktop_platform::linux::openwrt::OpenWrtServiceManager::new(
                    executor(),
                    None,
                ),
            );
        }
        Arc::new(diting_desktop_platform::linux::LinuxServiceManager::new(
            executor(),
            None,
        ))
    }
}

pub fn firewall_manager() -> Arc<dyn FirewallManager> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsFirewall::new(
            executor(),
        ))
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return Arc::new(
                diting_desktop_platform::linux::openwrt::OpenWrtFirewall::new(executor()),
            );
        }
        Arc::new(diting_desktop_platform::linux::LinuxFirewall::new(
            executor(),
        ))
    }
}

pub fn autostart_manager() -> Arc<dyn AutoStartManager> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsAutoStart::new())
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return Arc::new(diting_desktop_platform::linux::openwrt::OpenWrtAutoStart::new());
        }
        Arc::new(diting_desktop_platform::linux::LinuxAutoStart::new())
    }
}

pub fn firewall_backend_name() -> String {
    #[cfg(windows)]
    {
        diting_desktop_platform::windows::FIREWALL_BACKEND_NAME.to_string()
    }
    #[cfg(unix)]
    {
        if is_openwrt() {
            return diting_desktop_platform::linux::openwrt::detect_firewall_gen()
                .as_str()
                .to_string();
        }
        diting_desktop_platform::linux::firewall_backend_name()
    }
}

pub fn platform_handles(
    store: Arc<dyn StateStore>,
    dns_manager: Arc<dyn DnsManager>,
    openwrt: Option<Arc<dyn OpenWrtPlatform>>,
) -> PlatformHandles {
    let lan: Arc<dyn Fn() -> Vec<String> + Send + Sync> =
        Arc::new(|| lan_addresses().unwrap_or_default());
    PlatformHandles {
        adapters: Some(adapter_scanner()),
        port_checker: Some(port_checker(Some(Arc::clone(&dns_manager)))),
        dns_manager: Some(dns_manager),
        service_manager: Some(service_manager()),
        firewall: Some(firewall_manager()),
        autostart: Some(autostart_manager()),
        state_store: Some(store),
        openwrt,
        lan_addresses: lan,
        platform_name: std::env::consts::OS.to_string(),
        platform_kind: platform_kind(),
        distro_name: distro_name(),
        firewall_backend: firewall_backend_name(),
        is_elevated: is_elevated(),
    }
}

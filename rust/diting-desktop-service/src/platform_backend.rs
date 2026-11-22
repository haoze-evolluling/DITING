use std::sync::Arc;

use diting_desktop_app::PlatformHandles;
use diting_desktop_platform::error::PlatformResult;
use diting_desktop_platform::exec::{CommandExecutor, SystemExecutor};
use diting_desktop_platform::traits::{
    AdapterScanner, AutoStartManager, DnsManager, FirewallManager, PortChecker, ServiceManager,
    StateStore,
};

pub fn executor() -> Arc<dyn CommandExecutor> {
    Arc::new(SystemExecutor::new())
}

pub fn is_elevated() -> bool {
    diting_desktop_platform::privilege::is_elevated()
}

pub fn lan_addresses() -> PlatformResult<Vec<String>> {
    #[cfg(windows)]
    {
        diting_desktop_platform::windows::lan_addresses()
    }
    #[cfg(unix)]
    {
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
        diting_desktop_platform::linux::PLATFORM_DISPLAY_NAME
    }
}

pub fn port_check_hint() -> &'static str {
    #[cfg(windows)]
    {
        diting_desktop_platform::windows::PORT_CHECK_HINT
    }
    #[cfg(unix)]
    {
        diting_desktop_platform::linux::PORT_CHECK_HINT
    }
}

pub fn dns_manager(store: Arc<dyn StateStore>, version: &str) -> Arc<dyn DnsManager> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsDnsManager::new(
            executor(),
            store,
            version,
        ))
    }
    #[cfg(unix)]
    {
        Arc::new(diting_desktop_platform::linux::LinuxDnsManager::new(
            executor(),
            store,
            version,
        ))
    }
}

pub fn adapter_scanner() -> Arc<dyn AdapterScanner> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsAdapterScanner::new(executor()))
    }
    #[cfg(unix)]
    {
        Arc::new(diting_desktop_platform::linux::LinuxAdapterScanner::new(
            executor(),
        ))
    }
}

pub fn port_checker() -> Arc<dyn PortChecker> {
    #[cfg(windows)]
    {
        Arc::new(diting_desktop_platform::windows::WindowsPortChecker::new(
            executor(),
        ))
    }
    #[cfg(unix)]
    {
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
        diting_desktop_platform::linux::firewall_backend_name()
    }
}

pub fn platform_handles(
    store: Arc<dyn StateStore>,
    dns_manager: Arc<dyn DnsManager>,
) -> PlatformHandles {
    let lan: Arc<dyn Fn() -> Vec<String> + Send + Sync> =
        Arc::new(|| lan_addresses().unwrap_or_default());
    PlatformHandles {
        adapters: Some(adapter_scanner()),
        dns_manager: Some(dns_manager),
        port_checker: Some(port_checker()),
        service_manager: Some(service_manager()),
        firewall: Some(firewall_manager()),
        autostart: Some(autostart_manager()),
        state_store: Some(store),
        lan_addresses: lan,
        platform_name: std::env::consts::OS.to_string(),
        firewall_backend: firewall_backend_name(),
        is_elevated: is_elevated(),
    }
}

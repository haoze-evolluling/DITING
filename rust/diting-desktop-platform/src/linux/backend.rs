//! DNS backend detection and dispatch.
//!
//! Detection order matches Go: systemd-resolved → NetworkManager → direct `/etc/resolv.conf`.

mod networkmanager;
mod resolvconf;
mod resolved;

use std::collections::HashSet;

use diting_desktop_api::platform_types::{AdapterInfo, AdapterState};

use crate::error::PlatformResult;
use crate::exec::CommandExecutor;
use crate::netutil::is_loopback_or_local_ip;

use super::dnsstate::command_exists;

/// The system facility used to own per-interface DNS.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DnsBackend {
    /// No manageable backend was detected.
    None,
    /// `systemd-resolved` via `resolvectl`.
    SystemdResolved,
    /// NetworkManager via `nmcli`.
    NetworkManager,
    /// The static `/etc/resolv.conf` file.
    ResolvConf,
}

impl DnsBackend {
    pub fn as_str(self) -> &'static str {
        match self {
            DnsBackend::SystemdResolved => "systemd-resolved",
            DnsBackend::NetworkManager => "NetworkManager",
            DnsBackend::ResolvConf => "resolv.conf",
            DnsBackend::None => "none",
        }
    }
}

/// Detects the active backend without modifying any system configuration.
pub async fn detect_backend(executor: &dyn CommandExecutor) -> DnsBackend {
    if is_systemd_resolved_active(executor).await {
        return DnsBackend::SystemdResolved;
    }
    if is_network_manager_active(executor).await {
        return DnsBackend::NetworkManager;
    }
    DnsBackend::ResolvConf
}

async fn is_systemd_resolved_active(executor: &dyn CommandExecutor) -> bool {
    if !command_exists("resolvectl") {
        return false;
    }
    match executor.run("resolvectl", &["status"]).await {
        Ok(output) => output.success && !output.text().is_empty(),
        Err(_) => false,
    }
}

async fn is_network_manager_active(executor: &dyn CommandExecutor) -> bool {
    if !command_exists("nmcli") {
        return false;
    }
    match executor
        .run("nmcli", &["-t", "-f", "RUNNING", "general"])
        .await
    {
        Ok(output) => output.success && output.text() == "running",
        Err(_) => false,
    }
}

/// Points the selected adapters at the local loopback resolver.
pub(crate) async fn apply(
    executor: &dyn CommandExecutor,
    backend: DnsBackend,
    adapters: &[AdapterInfo],
) -> PlatformResult<()> {
    match backend {
        DnsBackend::SystemdResolved => resolved::apply(executor, adapters).await,
        DnsBackend::NetworkManager => networkmanager::apply(executor, adapters).await,
        DnsBackend::ResolvConf | DnsBackend::None => resolvconf::apply(executor).await,
    }
}

/// Restores adapters from a pre-takeover snapshot.
pub(crate) async fn restore(
    executor: &dyn CommandExecutor,
    backend: DnsBackend,
    adapters: &[AdapterState],
) -> PlatformResult<()> {
    match backend {
        DnsBackend::SystemdResolved => resolved::restore(executor, adapters).await,
        DnsBackend::NetworkManager => networkmanager::restore(executor, adapters).await,
        DnsBackend::ResolvConf | DnsBackend::None => resolvconf::restore(executor, adapters).await,
    }
}

/// Flushes the resolver cache owned by the backend, if any.
pub(crate) async fn flush(
    executor: &dyn CommandExecutor,
    backend: DnsBackend,
) -> PlatformResult<()> {
    match backend {
        DnsBackend::SystemdResolved => resolved::flush(executor).await,
        DnsBackend::NetworkManager => networkmanager::flush(executor).await,
        DnsBackend::ResolvConf | DnsBackend::None => resolvconf::flush(executor).await,
    }
}

/// Interface name used in backend commands (ID, then Name).
pub(crate) fn interface_name_from_adapter(adapter: &AdapterInfo) -> &str {
    if adapter.id.is_empty() {
        &adapter.name
    } else {
        &adapter.id
    }
}

/// Interface name used when restoring a snapshot.
pub(crate) fn interface_name_from_state(adapter: &AdapterState) -> &str {
    if adapter.id.is_empty() {
        &adapter.name
    } else {
        &adapter.id
    }
}

/// True when a server address is our own loopback takeover address.
pub(crate) fn is_residual_loopback_server(server: &str) -> bool {
    is_loopback_or_local_ip(server)
}

/// Merges IPv4 and IPv6 snapshot servers, dropping blanks, duplicates and loopback addresses.
pub(crate) fn merge_dual_stack_servers(adapter: &AdapterState) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut servers = Vec::new();
    for server in adapter.ipv4_dns.iter().chain(adapter.ipv6_dns.iter()) {
        let server = server.trim();
        if server.is_empty() || seen.contains(server) || is_residual_loopback_server(server) {
            continue;
        }
        seen.insert(server.to_string());
        servers.push(server.to_string());
    }
    servers
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_names_match_go() {
        assert_eq!(DnsBackend::None.as_str(), "none");
        assert_eq!(DnsBackend::SystemdResolved.as_str(), "systemd-resolved");
        assert_eq!(DnsBackend::NetworkManager.as_str(), "NetworkManager");
        assert_eq!(DnsBackend::ResolvConf.as_str(), "resolv.conf");
    }

    #[test]
    fn dual_stack_merge_skips_loopback_and_duplicates() {
        let adapter = AdapterState {
            ipv4_dns: vec!["1.1.1.1".into(), "127.0.0.1".into(), "".into()],
            ipv6_dns: vec!["1.1.1.1".into(), "2001:db8::1".into(), "::1".into()],
            ..AdapterState::default()
        };
        assert_eq!(
            merge_dual_stack_servers(&adapter),
            vec!["1.1.1.1".to_string(), "2001:db8::1".to_string()]
        );
    }
}

//! Firewall detection and port opening for firewalld, ufw, nftables and iptables.
//!
//! Detection order and commands match `desktop/service/internal/platform/linux/firewall.go`.

use std::sync::Arc;

use async_trait::async_trait;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::FirewallManager;

use super::dnsstate::command_exists;

/// Default web console port.
const DEFAULT_WEB_PORT: i32 = 15353;

/// Detected firewall management backend.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FirewallBackend {
    None,
    Firewalld,
    Ufw,
    Nftables,
    Iptables,
}

impl FirewallBackend {
    pub fn as_str(self) -> &'static str {
        match self {
            FirewallBackend::Firewalld => "firewalld",
            FirewallBackend::Ufw => "ufw",
            FirewallBackend::Nftables => "nftables",
            FirewallBackend::Iptables => "iptables",
            FirewallBackend::None => "none",
        }
    }
}

/// Detects the available firewall manager: firewalld → ufw → nftables → iptables.
pub fn detect_firewall_manager() -> FirewallBackend {
    if command_exists("firewall-cmd") {
        FirewallBackend::Firewalld
    } else if command_exists("ufw") {
        FirewallBackend::Ufw
    } else if command_exists("nft") {
        FirewallBackend::Nftables
    } else if command_exists("iptables") {
        FirewallBackend::Iptables
    } else {
        FirewallBackend::None
    }
}

/// Whether 53/udp and 53/tcp inbound rules exist. No firewall means the ports are already open.
pub async fn check_firewall_port53(executor: &dyn CommandExecutor) -> PlatformResult<bool> {
    let manager = detect_firewall_manager();
    if manager == FirewallBackend::None {
        return Ok(false);
    }
    if !check_firewall_rule_for_port(executor, manager, 53, "udp").await {
        return Ok(false);
    }
    Ok(check_firewall_rule_for_port(executor, manager, 53, "tcp").await)
}

/// Adds or removes 53/udp and 53/tcp inbound rules.
pub async fn configure_firewall_port53(
    executor: &dyn CommandExecutor,
    enable: bool,
) -> PlatformResult<()> {
    let manager = detect_firewall_manager();
    if manager == FirewallBackend::None {
        return Err(unsupported(
            "配置 53 端口防火墙规则（未检测到 firewalld / ufw / nftables / iptables）",
        ));
    }
    configure_firewall_rule_for_port(executor, manager, 53, "udp", enable).await?;
    configure_firewall_rule_for_port(executor, manager, 53, "tcp", enable).await
}

/// Whether the web console port has an inbound rule.
pub async fn check_firewall_port_web(executor: &dyn CommandExecutor) -> PlatformResult<bool> {
    let manager = detect_firewall_manager();
    if manager == FirewallBackend::None {
        return Ok(false);
    }
    Ok(check_firewall_rule_for_port(executor, manager, DEFAULT_WEB_PORT, "tcp").await)
}

/// Adds or removes the web console inbound rule.
pub async fn configure_firewall_port_web(
    executor: &dyn CommandExecutor,
    port: i32,
    enable: bool,
) -> PlatformResult<()> {
    let port = if port <= 0 { DEFAULT_WEB_PORT } else { port };
    let manager = detect_firewall_manager();
    if manager == FirewallBackend::None {
        return Err(unsupported(
            "配置 Web 管理端口防火墙规则（未检测到 firewalld / ufw / nftables / iptables）",
        ));
    }
    configure_firewall_rule_for_port(executor, manager, port, "tcp", enable).await
}

async fn check_firewall_rule_for_port(
    executor: &dyn CommandExecutor,
    manager: FirewallBackend,
    port: i32,
    protocol: &str,
) -> bool {
    match manager {
        FirewallBackend::Firewalld => {
            let rule = format!("{port}/{protocol}");
            match executor.run("firewall-cmd", &["--query-port", &rule]).await {
                Ok(output) => output.text().to_ascii_lowercase().contains("yes"),
                Err(_) => false,
            }
        }
        FirewallBackend::Ufw => match executor.run("ufw", &["status"]).await {
            Ok(output) => ufw_rule_present(&output.text(), port, protocol),
            Err(_) => false,
        },
        FirewallBackend::Iptables => {
            match executor
                .run(iptables_binary(protocol), &["-S", "INPUT"])
                .await
            {
                Ok(output) => output.text().contains(&format!("--dport {port}")),
                Err(_) => false,
            }
        }
        // nftables' rule language cannot be matched reliably; the configure path is idempotent.
        FirewallBackend::Nftables | FirewallBackend::None => false,
    }
}

async fn configure_firewall_rule_for_port(
    executor: &dyn CommandExecutor,
    manager: FirewallBackend,
    port: i32,
    protocol: &str,
    enable: bool,
) -> PlatformResult<()> {
    match manager {
        FirewallBackend::Firewalld => {
            let operation = if enable {
                "--add-port"
            } else {
                "--remove-port"
            };
            let rule = format!("{port}/{protocol}");
            executor
                .run_checked("firewall-cmd", &["--permanent", operation, &rule])
                .await
                .map_err(|error| {
                    PlatformError::message(format!(
                        "firewalld 配置 {port}/{protocol} 失败: {error}"
                    ))
                })?;
            executor
                .run_checked("firewall-cmd", &["--reload"])
                .await
                .map(|_| ())
        }
        FirewallBackend::Ufw => {
            let rule = format!("{port}/{protocol}");
            if enable {
                executor
                    .run_checked("ufw", &["allow", &rule])
                    .await
                    .map(|_| ())
            } else {
                executor
                    .run_checked("ufw", &["delete", "allow", &rule])
                    .await
                    .map(|_| ())
            }
        }
        FirewallBackend::Iptables => {
            configure_iptables_rule(executor, port, protocol, enable).await
        }
        FirewallBackend::Nftables => configure_nft_rule(executor, port, protocol, enable).await,
        FirewallBackend::None => Err(unsupported("配置防火墙规则")),
    }
}

async fn configure_iptables_rule(
    executor: &dyn CommandExecutor,
    port: i32,
    protocol: &str,
    enable: bool,
) -> PlatformResult<()> {
    let operation = if enable { "-A" } else { "-D" };
    let port_arg = port.to_string();
    let args = [
        operation, "INPUT", "-p", protocol, "--dport", &port_arg, "-j", "ACCEPT",
    ];
    match executor.run(iptables_binary(protocol), &args).await {
        // Deleting a missing rule errors; treat it as idempotent success.
        Err(_) if !enable => Ok(()),
        Err(error) => Err(PlatformError::message(format!(
            "iptables 配置 {port}/{protocol} 失败: {error}"
        ))),
        Ok(_) => Ok(()),
    }
}

async fn configure_nft_rule(
    executor: &dyn CommandExecutor,
    port: i32,
    protocol: &str,
    enable: bool,
) -> PlatformResult<()> {
    if !enable {
        // Deleting a missing table errors; ignore to stay idempotent.
        let _ = executor
            .run("nft", &["delete", "table", "inet", "diting"])
            .await;
        return Ok(());
    }

    let script = format!(
        "nft 'add table inet diting' 2>/dev/null; \
         nft 'add chain inet diting input {{ type filter hook input priority 0; }}' 2>/dev/null; \
         nft 'add rule inet diting input {protocol} dport {port} accept' 2>/dev/null; true"
    );
    executor
        .run_checked("sh", &["-c", &script])
        .await
        .map(|_| ())
        .map_err(|error| {
            PlatformError::message(format!("nftables 配置 {port}/{protocol} 失败: {error}"))
        })
}

fn iptables_binary(protocol: &str) -> &'static str {
    if protocol.ends_with('6') {
        "ip6tables"
    } else {
        "iptables"
    }
}

fn ufw_rule_present(status_output: &str, port: i32, protocol: &str) -> bool {
    let target = format!("{port}/{protocol}");
    status_output.lines().any(|line| {
        let lower = line.trim().to_ascii_lowercase();
        lower.starts_with(&target) && lower.contains("allow")
    })
}

fn unsupported(operation: &str) -> PlatformError {
    PlatformError::message(format!("当前平台 (linux) 不支持该操作: {operation}"))
}

/// Linux firewall manager adapter.
pub struct LinuxFirewall {
    executor: Arc<dyn CommandExecutor>,
}

impl LinuxFirewall {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self { executor }
    }
}

#[async_trait]
impl FirewallManager for LinuxFirewall {
    async fn check_port53(&self) -> PlatformResult<bool> {
        check_firewall_port53(self.executor.as_ref()).await
    }

    async fn configure_port53(&self, enable: bool) -> PlatformResult<()> {
        configure_firewall_port53(self.executor.as_ref(), enable).await
    }

    async fn check_web(&self) -> PlatformResult<bool> {
        check_firewall_port_web(self.executor.as_ref()).await
    }

    async fn configure_web(&self, port: i32, enable: bool) -> PlatformResult<()> {
        configure_firewall_port_web(self.executor.as_ref(), port, enable).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ufw_rules_are_matched_by_prefix() {
        let output = "Status: active\n\nTo                         Action      From\n\
                      --                         ------      ----\n\
                      53/udp                     ALLOW       Anywhere\n\
                      15353/tcp                  ALLOW       Anywhere\n";
        assert!(ufw_rule_present(output, 53, "udp"));
        assert!(ufw_rule_present(output, 15353, "tcp"));
        assert!(!ufw_rule_present(output, 53, "tcp"));
    }

    #[test]
    fn iptables_binary_switches_for_ipv6() {
        assert_eq!(iptables_binary("udp"), "iptables");
        assert_eq!(iptables_binary("tcp6"), "ip6tables");
    }
}

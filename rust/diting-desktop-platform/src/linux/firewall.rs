use std::sync::Arc;

use async_trait::async_trait;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::FirewallManager;

use super::dnsstate::command_exists;

const DEFAULT_WEB_PORT: i32 = 15353;

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

pub async fn check_firewall_port_web(executor: &dyn CommandExecutor) -> PlatformResult<bool> {
    let manager = detect_firewall_manager();
    if manager == FirewallBackend::None {
        return Ok(false);
    }
    Ok(check_firewall_rule_for_port(executor, manager, DEFAULT_WEB_PORT, "tcp").await)
}

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
                Ok(output) => iptables_rule_present(&output.text(), port, protocol),
                Err(_) => false,
            }
        }
        FirewallBackend::Nftables => nft_rule_present(executor, port, protocol).await,
        FirewallBackend::None => false,
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
    let binary = iptables_binary(protocol);
    let port_arg = port.to_string();
    if enable {
        // -C 先探测，避免重复追加规则；-A 必须检查退出码，否则失败会被当成成功。
        if let Ok(output) = executor
            .run(
                binary,
                &[
                    "-C", "INPUT", "-p", protocol, "--dport", &port_arg, "-j", "ACCEPT",
                ],
            )
            .await
        {
            if output.success {
                return Ok(());
            }
        }
        return executor
            .run_checked(
                binary,
                &[
                    "-A", "INPUT", "-p", protocol, "--dport", &port_arg, "-j", "ACCEPT",
                ],
            )
            .await
            .map(|_| ())
            .map_err(|error| {
                PlatformError::message(format!("iptables 配置 {port}/{protocol} 失败: {error}"))
            });
    }

    let _ = executor
        .run(
            binary,
            &[
                "-D", "INPUT", "-p", protocol, "--dport", &port_arg, "-j", "ACCEPT",
            ],
        )
        .await;
    Ok(())
}

const NFT_TABLE: &str = "diting";
const NFT_CHAIN: &str = "input";

fn nft_comment(port: i32, protocol: &str) -> String {
    format!("diting-{port}-{protocol}")
}

async fn nft_rule_present(executor: &dyn CommandExecutor, port: i32, protocol: &str) -> bool {
    match executor
        .run("nft", &["list", "table", "inet", NFT_TABLE])
        .await
    {
        Ok(output) if output.success => nft_rule_in_output(&output.text(), port, protocol),
        _ => false,
    }
}

async fn configure_nft_rule(
    executor: &dyn CommandExecutor,
    port: i32,
    protocol: &str,
    enable: bool,
) -> PlatformResult<()> {
    if !enable {
        // 只删除本端口的规则，绝不能删除整张表（会连带移除 53 端口等规则）。
        let output = match executor
            .run("nft", &["-a", "list", "table", "inet", NFT_TABLE])
            .await
        {
            Ok(output) if output.success => output,
            _ => return Ok(()),
        };
        let comment = nft_comment(port, protocol);
        for handle in nft_rule_handles(&output.text(), &comment) {
            executor
                .run_checked(
                    "nft",
                    &[
                        "delete", "rule", "inet", NFT_TABLE, NFT_CHAIN, "handle", &handle,
                    ],
                )
                .await
                .map_err(|error| {
                    PlatformError::message(format!(
                        "nftables 删除 {port}/{protocol} 规则失败: {error}"
                    ))
                })?;
        }
        return Ok(());
    }

    let ensure = "nft 'add table inet diting' 2>/dev/null || true; \
                  nft 'add chain inet diting input { type filter hook input priority 0; }' 2>/dev/null || true";
    executor
        .run_checked("sh", &["-c", ensure])
        .await
        .map_err(|error| PlatformError::message(format!("nftables 初始化表失败: {error}")))?;

    if nft_rule_present(executor, port, protocol).await {
        return Ok(());
    }

    let port_arg = port.to_string();
    let comment = nft_comment(port, protocol);
    executor
        .run_checked(
            "nft",
            &[
                "add", "rule", "inet", NFT_TABLE, NFT_CHAIN, protocol, "dport", &port_arg,
                "accept", "comment", &comment,
            ],
        )
        .await
        .map(|_| ())
        .map_err(|error| {
            PlatformError::message(format!("nftables 配置 {port}/{protocol} 失败: {error}"))
        })
}

pub(crate) fn nft_rule_in_output(output: &str, port: i32, protocol: &str) -> bool {
    let comment = nft_comment(port, protocol);
    let dport = format!("dport {port}");
    output.lines().any(|line| {
        let lower = line.to_ascii_lowercase();
        if lower.contains(&comment) {
            return true;
        }
        lower.contains(&dport) && lower.contains(protocol) && lower.contains("accept")
    })
}

pub(crate) fn nft_rule_handles(output: &str, comment: &str) -> Vec<String> {
    output
        .lines()
        .filter(|line| line.contains(comment))
        .filter_map(|line| {
            let index = line.rfind("# handle ")?;
            let handle = line[index + "# handle ".len()..].trim();
            (!handle.is_empty()).then(|| handle.to_string())
        })
        .collect()
}

pub(crate) fn iptables_rule_present(output: &str, port: i32, protocol: &str) -> bool {
    let dport = format!("--dport {port}");
    let family = format!("-p {protocol}");
    output
        .lines()
        .any(|line| line.contains(&dport) && line.contains(&family) && line.contains("-j ACCEPT"))
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

    #[test]
    fn nft_rules_are_detected_by_comment_or_signature() {
        let output = "table inet diting {\n\
                      \tchain input {\n\
                      \t\ttype filter hook input priority filter; policy accept;\n\
                      \t\ttcp dport 15353 accept comment \"diting-15353-tcp\"\n\
                      \t}\n\
                      }\n";
        assert!(nft_rule_in_output(output, 15353, "tcp"));
        assert!(!nft_rule_in_output(output, 53, "udp"));
    }

    #[test]
    fn nft_handles_are_collected_per_comment() {
        let output = "\t\ttcp dport 15353 accept comment \"diting-15353-tcp\" # handle 12\n\
                      \t\tudp dport 53 accept comment \"diting-53-udp\" # handle 13\n\
                      \t\ttcp dport 53 accept comment \"diting-53-tcp\" # handle 14\n";
        assert_eq!(nft_rule_handles(output, "diting-53-udp"), vec!["13"]);
        assert!(nft_rule_handles(output, "diting-9999-tcp").is_empty());
    }

    #[test]
    fn iptables_rules_require_protocol_and_accept() {
        let output = "-P INPUT ACCEPT\n\
                      -A INPUT -p udp -m udp --dport 53 -j ACCEPT\n\
                      -A INPUT -p tcp -m tcp --dport 53 -j DROP\n";
        assert!(iptables_rule_present(output, 53, "udp"));
        assert!(!iptables_rule_present(output, 53, "tcp"));
        assert!(!iptables_rule_present(output, 15353, "tcp"));
    }
}

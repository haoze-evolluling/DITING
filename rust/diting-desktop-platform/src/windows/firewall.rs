use std::sync::Arc;

use async_trait::async_trait;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::FirewallManager;

pub const FIREWALL_RULE_NAME_UDP: &str = "Diting DNS LAN Server (UDP)";
pub const FIREWALL_RULE_NAME_TCP: &str = "Diting DNS LAN Server (TCP)";
pub const FIREWALL_RULE_NAME_WEB: &str = "Diting Web Admin (TCP)";
const DEFAULT_WEB_PORT: i32 = 15_353;

pub(crate) fn is_firewall_rule_active(output: &str) -> bool {
    let mut enabled = false;
    let mut action_allow = false;
    for raw_line in output.lines() {
        let line = raw_line.trim();
        let lower = line.to_ascii_lowercase();
        if lower.starts_with("enabled:") || line.starts_with("已启用:") {
            enabled = lower.contains("yes") || line.contains('是');
        }
        if lower.starts_with("action:") || line.starts_with("操作:") {
            action_allow = lower.contains("allow") || line.contains("允许");
        }
    }
    enabled && action_allow
}

async fn run_netsh(executor: &dyn CommandExecutor, args: Vec<String>) -> PlatformResult<String> {
    let borrowed: Vec<&str> = args.iter().map(String::as_str).collect();
    let output = executor.run("netsh", &borrowed).await?;
    if output.success {
        Ok(output.text())
    } else {
        Err(PlatformError::message(format!(
            "netsh {} 失败: {}",
            borrowed.join(" "),
            output.text()
        )))
    }
}

async fn show_rule(executor: &dyn CommandExecutor, rule_name: &str) -> bool {
    let args = vec![
        "advfirewall".to_string(),
        "firewall".to_string(),
        "show".to_string(),
        "rule".to_string(),
        format!("name={rule_name}"),
    ];
    match run_netsh(executor, args).await {
        Ok(output) => is_firewall_rule_active(&output),
        Err(_) => false,
    }
}

async fn delete_rule(executor: &dyn CommandExecutor, rule_name: &str) -> PlatformResult<()> {
    let args = vec![
        "advfirewall".to_string(),
        "firewall".to_string(),
        "delete".to_string(),
        "rule".to_string(),
        format!("name={rule_name}"),
    ];
    run_netsh(executor, args).await.map(|_| ())
}

async fn add_rule(
    executor: &dyn CommandExecutor,
    rule_name: &str,
    protocol: &str,
    local_port: &str,
    description: &str,
) -> PlatformResult<()> {
    run_netsh(
        executor,
        vec![
            "advfirewall".to_string(),
            "firewall".to_string(),
            "add".to_string(),
            "rule".to_string(),
            format!("name={rule_name}"),
            "dir=in".to_string(),
            "action=allow".to_string(),
            format!("protocol={protocol}"),
            format!("localport={local_port}"),
            "profile=any".to_string(),
            format!("description={description}"),
        ],
    )
    .await
    .map(|_| ())
}

pub async fn check_firewall_port53(executor: &dyn CommandExecutor) -> PlatformResult<bool> {
    if !show_rule(executor, FIREWALL_RULE_NAME_UDP).await {
        return Ok(false);
    }
    Ok(show_rule(executor, FIREWALL_RULE_NAME_TCP).await)
}

pub async fn configure_firewall_port53(
    executor: &dyn CommandExecutor,
    enable: bool,
) -> PlatformResult<()> {
    let _ = delete_rule(executor, FIREWALL_RULE_NAME_UDP).await;
    let _ = delete_rule(executor, FIREWALL_RULE_NAME_TCP).await;
    if !enable {
        return Ok(());
    }

    if let Err(error) = add_rule(
        executor,
        FIREWALL_RULE_NAME_UDP,
        "UDP",
        "53",
        "谛听 DNS 局域网服务 UDP 端口放行",
    )
    .await
    {
        return Err(PlatformError::message(format!(
            "添加 UDP 53 防火墙规则失败: {error}"
        )));
    }
    if let Err(error) = add_rule(
        executor,
        FIREWALL_RULE_NAME_TCP,
        "TCP",
        "53",
        "谛听 DNS 局域网服务 TCP 端口放行",
    )
    .await
    {
        return Err(PlatformError::message(format!(
            "添加 TCP 53 防火墙规则失败: {error}"
        )));
    }
    Ok(())
}

pub async fn check_firewall_port_web(executor: &dyn CommandExecutor) -> PlatformResult<bool> {
    Ok(show_rule(executor, FIREWALL_RULE_NAME_WEB).await)
}

pub async fn configure_firewall_port_web(
    executor: &dyn CommandExecutor,
    port: i32,
    enable: bool,
) -> PlatformResult<()> {
    let port = if port <= 0 { DEFAULT_WEB_PORT } else { port };
    let _ = delete_rule(executor, FIREWALL_RULE_NAME_WEB).await;
    if !enable {
        return Ok(());
    }
    if let Err(error) = add_rule(
        executor,
        FIREWALL_RULE_NAME_WEB,
        "TCP",
        &port.to_string(),
        "谛听 Web 局域网远程管理端口放行",
    )
    .await
    {
        return Err(PlatformError::message(format!(
            "添加 Web 管理防火墙规则失败: {error}"
        )));
    }
    Ok(())
}

pub struct WindowsFirewall {
    executor: Arc<dyn CommandExecutor>,
}

impl WindowsFirewall {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self { executor }
    }
}

#[async_trait]
impl FirewallManager for WindowsFirewall {
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
    fn chinese_enabled_allow_is_active() {
        let output = "规则名称: Diting DNS LAN Server (UDP)\n已启用: 是\n操作: 允许\n";
        assert!(is_firewall_rule_active(output));
    }

    #[test]
    fn english_enabled_allow_is_active() {
        let output = "Rule Name: Diting DNS LAN Server (TCP)\nEnabled: Yes\nAction: Allow\n";
        assert!(is_firewall_rule_active(output));
    }

    #[test]
    fn disabled_or_block_is_inactive() {
        assert!(!is_firewall_rule_active(
            "Rule Name: x\nEnabled: No\nAction: Allow\n"
        ));
        assert!(!is_firewall_rule_active(
            "规则名称: x\n已启用: 否\n操作: 允许\n"
        ));
        assert!(!is_firewall_rule_active(
            "Rule Name: x\nEnabled: Yes\nAction: Block\n"
        ));
    }

    #[test]
    fn empty_output_is_inactive() {
        assert!(!is_firewall_rule_active(""));
    }
}

use std::sync::Arc;

use async_trait::async_trait;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::traits::FirewallManager;

use super::detect::{detect_firewall_gen, FirewallGen};
use super::uci;

const DEFAULT_WEB_PORT: i32 = 15353;
const RULE_DNS_LAN: &str = "firewall.diting_dns_lan";
const RULE_WEB_LAN: &str = "firewall.diting_web_lan";
const REDIRECT_DNS_LAN: &str = "firewall.diting_dns_redirect";

pub struct OpenWrtFirewall {
    executor: Arc<dyn CommandExecutor>,
}

impl OpenWrtFirewall {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self { executor }
    }

    pub async fn check_dns_redirect(&self) -> bool {
        check_section_enabled(self.executor.as_ref(), REDIRECT_DNS_LAN).await
    }

    pub async fn configure_dns_redirect(
        &self,
        enable: bool,
        target_port: u16,
    ) -> PlatformResult<()> {
        ensure_uci_available()?;
        let executor = self.executor.as_ref();
        if !enable {
            if !section_exists(executor, REDIRECT_DNS_LAN).await {
                return Ok(());
            }
            uci::delete_key(executor, REDIRECT_DNS_LAN).await?;
            return commit_and_reload_firewall(executor).await;
        }

        let port = target_port.to_string();
        uci::set_section(executor, REDIRECT_DNS_LAN, "redirect").await?;
        uci::set_option(
            executor,
            &format!("{REDIRECT_DNS_LAN}.name"),
            "DITING-Force-DNS-LAN",
        )
        .await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.src"), "lan").await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.proto"), "tcp udp").await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.src_dport"), "53").await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.dest_port"), &port).await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.target"), "DNAT").await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.family"), "any").await?;
        uci::set_option(executor, &format!("{REDIRECT_DNS_LAN}.enabled"), "1").await?;
        commit_and_reload_firewall(executor).await
    }

    pub async fn clear_all_diting_rules(&self) -> PlatformResult<()> {
        if detect_firewall_gen() == FirewallGen::None {
            return Ok(());
        }
        let executor = self.executor.as_ref();
        let mut touched = false;
        for section in [REDIRECT_DNS_LAN, RULE_DNS_LAN, RULE_WEB_LAN] {
            if section_exists(executor, section).await {
                uci::delete_key(executor, section).await?;
                touched = true;
            }
        }
        if touched {
            commit_and_reload_firewall(executor).await?;
        }
        Ok(())
    }
}

fn ensure_uci_available() -> PlatformResult<()> {
    if detect_firewall_gen() == FirewallGen::None {
        return Err(PlatformError::message(
            "未检测到 OpenWrt UCI 工具，无法配置防火墙规则",
        ));
    }
    Ok(())
}

async fn section_exists(executor: &dyn CommandExecutor, section: &str) -> bool {
    uci::get_option(executor, section).await.is_some()
}

async fn check_section_enabled(executor: &dyn CommandExecutor, section: &str) -> bool {
    if !section_exists(executor, section).await {
        return false;
    }
    match uci::get_option(executor, &format!("{section}.enabled")).await {
        Some(val) => !matches!(val.trim(), "0" | "false" | "no"),
        None => true,
    }
}

/// 严格限定仅放行 `src='lan'` 入站规则，绝不对 `wan` 公网开放端口。
async fn configure_lan_input_rule(
    executor: &dyn CommandExecutor,
    section: &str,
    name: &str,
    proto: &str,
    port: i32,
    enable: bool,
) -> PlatformResult<()> {
    ensure_uci_available()?;
    if !enable {
        if !section_exists(executor, section).await {
            return Ok(());
        }
        uci::delete_key(executor, section).await?;
        return commit_and_reload_firewall(executor).await;
    }

    let port_str = port.to_string();
    uci::set_section(executor, section, "rule").await?;
    uci::set_option(executor, &format!("{section}.name"), name).await?;
    uci::set_option(executor, &format!("{section}.src"), "lan").await?;
    uci::set_option(executor, &format!("{section}.proto"), proto).await?;
    uci::set_option(executor, &format!("{section}.dest_port"), &port_str).await?;
    uci::set_option(executor, &format!("{section}.target"), "ACCEPT").await?;
    uci::set_option(executor, &format!("{section}.enabled"), "1").await?;
    commit_and_reload_firewall(executor).await
}

async fn commit_and_reload_firewall(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    uci::commit(executor, "firewall").await?;
    // reload 失败在测试容器或精简环境中降级尝试 fw4/fw3 reload。
    if uci::init_action(executor, "firewall", "reload")
        .await
        .is_err()
    {
        match detect_firewall_gen() {
            FirewallGen::Fw4 => {
                let _ = executor.run("fw4", &["reload"]).await;
            }
            FirewallGen::Fw3 => {
                let _ = executor.run("fw3", &["reload"]).await;
            }
            _ => {}
        }
    }
    Ok(())
}

#[async_trait]
impl FirewallManager for OpenWrtFirewall {
    async fn check_port53(&self) -> PlatformResult<bool> {
        // OpenWrt 默认 lan -> input 即为 ACCEPT；存在显式规则或 lan 默认放行均可正常服务。
        if check_section_enabled(self.executor.as_ref(), RULE_DNS_LAN).await {
            return Ok(true);
        }
        Ok(lan_zone_default_accepts_input(self.executor.as_ref()).await)
    }

    async fn configure_port53(&self, enable: bool) -> PlatformResult<()> {
        configure_lan_input_rule(
            self.executor.as_ref(),
            RULE_DNS_LAN,
            "DITING-DNS-LAN",
            "tcp udp",
            53,
            enable,
        )
        .await
    }

    async fn check_web(&self) -> PlatformResult<bool> {
        if check_section_enabled(self.executor.as_ref(), RULE_WEB_LAN).await {
            return Ok(true);
        }
        Ok(lan_zone_default_accepts_input(self.executor.as_ref()).await)
    }

    async fn configure_web(&self, port: i32, enable: bool) -> PlatformResult<()> {
        let port = if port <= 0 { DEFAULT_WEB_PORT } else { port };
        configure_lan_input_rule(
            self.executor.as_ref(),
            RULE_WEB_LAN,
            "DITING-Web-LAN",
            "tcp",
            port,
            enable,
        )
        .await
    }
}

async fn lan_zone_default_accepts_input(executor: &dyn CommandExecutor) -> bool {
    for index in 0..8 {
        let name_key = format!("firewall.@zone[{index}].name");
        let Some(name) = uci::get_option(executor, &name_key).await else {
            break;
        };
        if name.trim() == "lan" {
            let input_key = format!("firewall.@zone[{index}].input");
            return uci::get_option(executor, &input_key)
                .await
                .is_some_and(|val| val.trim().eq_ignore_ascii_case("ACCEPT"));
        }
    }
    false
}

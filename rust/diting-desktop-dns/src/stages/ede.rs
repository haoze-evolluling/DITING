use async_trait::async_trait;
use diting_dns_wire::build::{parse_opt, ParsedMessage};

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{add_ede, attr_is_true};
use crate::stages::ConfigHandle;

pub const EDE_BLOCKED: u16 = 15;
pub const EDE_PROHIBITED: u16 = 18;
pub const EDE_CACHED_ERROR: u16 = 13;
pub const EDE_NETWORK_ERROR: u16 = 23;

pub struct EdeStage {
    config: ConfigHandle,
}

impl EdeStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for EdeStage {
    fn name(&self) -> &'static str {
        "ede"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        let enabled = self
            .config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .dns
            .enable_ede;
        if !enabled || parse_opt(&ctx.request).is_none() {
            return;
        }
        let Some(response) = ctx.response.take() else {
            return;
        };
        let Some(mut message) = ParsedMessage::parse(&response) else {
            ctx.response = Some(response);
            return;
        };
        if let Some((code, text)) = describe(ctx) {
            add_ede(&mut message, code, &text);
            ctx.response = message.to_wire().or(Some(response));
        } else {
            ctx.response = Some(response);
        }
    }
}

fn describe(ctx: &DnsContext) -> Option<(u16, String)> {
    let reason = ctx.get("filter_reason").unwrap_or("").trim().to_string();
    let prefixed = |fallback: &str| {
        if reason.is_empty() {
            format!("DITING: {fallback}")
        } else {
            format!("DITING: {reason}")
        }
    };
    if attr_is_true(ctx, "access_blocked") {
        return Some((
            EDE_PROHIBITED,
            prefixed("Client query prohibited by access policy"),
        ));
    }
    if attr_is_true(ctx, "ratelimit_blocked") {
        return Some((EDE_PROHIBITED, prefixed("Client query rate limit exceeded")));
    }
    if attr_is_true(ctx, "rebinding_blocked") {
        return Some((
            EDE_PROHIBITED,
            prefixed("Blocked by DNS rebinding protection"),
        ));
    }
    if attr_is_true(ctx, "unqualified_blocked") {
        return Some((EDE_BLOCKED, prefixed("Blocked unqualified domain leak")));
    }
    if attr_is_true(ctx, "any_blocked") {
        return Some((
            EDE_BLOCKED,
            "DITING: ANY 查询已按 RFC 8482 最小化应答".to_string(),
        ));
    }
    if attr_is_true(ctx, "bogus_nxdomain") {
        return Some((
            EDE_BLOCKED,
            "DITING: 上游返回劫持地址，已纠正为 NXDOMAIN".to_string(),
        ));
    }
    if attr_is_true(ctx, "filter_blocked") {
        return Some((EDE_BLOCKED, prefixed("Blocked by filter rule")));
    }
    if ctx.error.is_some() {
        return Some((
            EDE_NETWORK_ERROR,
            format!(
                "DITING: {}",
                ctx.error.as_deref().unwrap_or("Upstream resolution failed")
            ),
        ));
    }
    if ctx.get("cache_hit") == Some("stale") {
        return Some((
            EDE_CACHED_ERROR,
            "DITING: Stale cache response (network degraded)".to_string(),
        ));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{EdnsOption, MessageBuilder, OptBuilder, OPTION_EDE};

    #[tokio::test]
    async fn adds_blocked_ede_when_client_sent_opt() {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        let stage = EdeStage::new(config);
        let query = MessageBuilder::query("ads.example", 1, 1)
            .with_opt(OptBuilder::new(1232))
            .finish()
            .unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        ctx.set("filter_blocked", "true");
        ctx.set("filter_reason", "blocked by list");
        ctx.reply_with_rcode(3);
        stage.after(&mut ctx).await;
        let message = ParsedMessage::parse(&ctx.response.unwrap()).unwrap();
        let option = message
            .opt_options()
            .iter()
            .find(|option| option.code() == OPTION_EDE)
            .cloned();
        match option {
            Some(EdnsOption::Ede(ede)) => {
                assert_eq!(ede.code, EDE_BLOCKED);
                assert!(ede.text.contains("blocked by list"));
            }
            _ => panic!("expected EDE option"),
        }
    }

    #[tokio::test]
    async fn no_opt_means_no_ede() {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        let stage = EdeStage::new(config);
        let query = MessageBuilder::query("ads.example", 1, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        ctx.set("filter_blocked", "true");
        ctx.reply_with_rcode(3);
        let before = ctx.response.clone().unwrap();
        stage.after(&mut ctx).await;
        assert_eq!(ctx.response.unwrap(), before);
    }
}

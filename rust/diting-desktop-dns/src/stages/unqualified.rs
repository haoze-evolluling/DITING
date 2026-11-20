use async_trait::async_trait;

use crate::context::{DnsContext, RCODE_NXDOMAIN};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{normalized_name, respond, start_reply};
use crate::stages::ConfigHandle;

pub struct UnqualifiedStage {
    config: ConfigHandle,
}

impl UnqualifiedStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for UnqualifiedStage {
    fn name(&self) -> &'static str {
        "unqualified"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let enabled = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            config.dns.block_unqualified
        };
        if !enabled {
            return StageResult::Continue;
        }
        let name = normalized_name(&ctx.question.name);
        if name.is_empty() || name.contains('.') {
            return StageResult::Continue;
        }
        let Some(builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        respond(ctx, builder.set_rcode(RCODE_NXDOMAIN));
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", "BLOCK_UNQUALIFIED");
        ctx.set("filter_reason", "Unqualified domain name leak blocked");
        ctx.set("unqualified_blocked", "true");
        StageResult::Stop
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::MessageBuilder;

    async fn run(name: &str, enabled: bool) -> Option<DnsContext> {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        config.write().unwrap().dns.block_unqualified = enabled;
        let stage = UnqualifiedStage::new(config);
        let query = MessageBuilder::query(name, 1, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        let result = stage.before(&mut ctx).await;
        (result == StageResult::Stop).then_some(ctx)
    }

    #[tokio::test]
    async fn blocks_bare_labels_only() {
        assert!(run("nas", true).await.is_some());
        assert!(run("nas.lan", true).await.is_none());
        assert!(run("nas", false).await.is_none());
    }
}

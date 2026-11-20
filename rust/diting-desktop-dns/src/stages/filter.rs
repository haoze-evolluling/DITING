use async_trait::async_trait;
use diting_desktop_core::filter::{
    CheckHostResult, RuleEngine, VerdictAction, REASON_SCHEDULE_INACTIVE,
    REASON_SERVICE_SCHEDULE_INACTIVE,
};
use diting_dns_wire::build::MessageBuilder;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::block::respond_blocked;
use crate::stages::records::to_wire_record;
use crate::stages::util::{normalized_name, respond};

pub struct FilterStage {
    engine: RuleEngine,
}

impl FilterStage {
    pub fn new(engine: RuleEngine) -> Self {
        Self { engine }
    }
}

#[async_trait]
impl Stage for FilterStage {
    fn name(&self) -> &'static str {
        "filter"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.engine.is_enabled() {
            return StageResult::Continue;
        }
        let domain = normalized_name(&ctx.question.name);
        if domain.is_empty() {
            return StageResult::Continue;
        }
        let verdict = self.engine.check(&domain, ctx.question.qtype, &ctx.group);
        if verdict.action == VerdictAction::Pass && verdict.reason == REASON_SCHEDULE_INACTIVE {
            ctx.set("filter_action", "pass");
            ctx.set("filter_blocked", "false");
            ctx.set("filter_reason", &verdict.reason);
            ctx.set("filter_schedule_inactive", "true");
            return StageResult::Continue;
        }
        if verdict.action == VerdictAction::Pass
            && verdict.reason == REASON_SERVICE_SCHEDULE_INACTIVE
        {
            ctx.set("filter_action", "pass");
            ctx.set("filter_blocked", "false");
            ctx.set("filter_reason", &verdict.reason);
            ctx.set("filter_service_schedule_inactive", "true");
            return StageResult::Continue;
        }
        if verdict.is_rewrite() {
            self.answer_rewrite(ctx, &verdict);
            return StageResult::Stop;
        }
        if verdict.blocked {
            let policy = self.engine.block_response_config(&ctx.group);
            respond_blocked(ctx, &policy);
            apply_verdict(ctx, &verdict, "block");
            ctx.set("filter_blocked", "true");
            return StageResult::Stop;
        }
        if verdict.action == VerdictAction::Allow {
            apply_verdict(ctx, &verdict, "allow");
            ctx.set("filter_blocked", "false");
        }
        StageResult::Continue
    }
}

fn apply_verdict(ctx: &mut DnsContext, verdict: &CheckHostResult, action: &str) {
    ctx.set("filter_action", action);
    ctx.set("filter_rule", &verdict.matched_rule);
    ctx.set("filter_reason", &verdict.reason);
    ctx.set("filter_list", &verdict.list_name);
}

impl FilterStage {
    fn answer_rewrite(&self, ctx: &mut DnsContext, verdict: &CheckHostResult) {
        let Some(rewrite) = &verdict.rewritten else {
            return;
        };
        let Some(mut builder) = MessageBuilder::reply_to(&ctx.request) else {
            return;
        };
        builder = builder
            .set_authoritative(true)
            .set_recursion_available(true)
            .set_rcode(rewrite.rcode);
        if rewrite.rcode == 0 {
            for record in &rewrite.records {
                if let Ok(Some(parsed)) = diting_rewrite_core::record::build(
                    &ctx.question.name,
                    ctx.question.qtype,
                    &record.kind,
                    &record.value,
                    record.ttl,
                ) {
                    if let Some(wire) = to_wire_record(&parsed) {
                        builder = builder.push_answer(wire);
                    }
                }
            }
        }
        respond(ctx, builder);
        apply_verdict(ctx, verdict, "rewrite");
        ctx.set("filter_blocked", "false");
        ctx.set("source", "dnsrewrite");
        ctx.set("cache_hit", "dnsrewrite");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_api::config::Config;

    fn engine(config: Config) -> RuleEngine {
        RuleEngine::new(config.filter)
    }

    #[tokio::test]
    async fn custom_block_answer_uses_the_block_mode() {
        let mut config = Config::default();
        config.filter.enabled = true;
        config.filter.custom_rules = vec!["||ads.example^".to_string()];
        config.filter.block_mode = "nxdomain".to_string();
        let stage = FilterStage::new(engine(config));
        let query = MessageBuilder::query("ads.example", 1, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        assert_eq!(stage.before(&mut ctx).await, StageResult::Stop);
        assert_eq!(ctx.get("filter_blocked"), Some("true"));
        let header = diting_dns_wire::parse_header(ctx.response.as_ref().unwrap()).unwrap();
        assert_eq!(header.flags & 0x0f, 3);
    }

    #[tokio::test]
    async fn rewrite_returns_authoritative_records() {
        let mut config = Config::default();
        config.filter.enabled = true;
        config.filter.custom_rules = vec!["||nas.lan^$dnsrewrite=192.168.1.5".to_string()];
        let stage = FilterStage::new(engine(config));
        let query = MessageBuilder::query("nas.lan", 1, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        assert_eq!(stage.before(&mut ctx).await, StageResult::Stop);
        assert_eq!(ctx.get("source"), Some("dnsrewrite"));
        let message =
            diting_dns_wire::build::ParsedMessage::parse(ctx.response.as_ref().unwrap()).unwrap();
        assert_eq!(message.answers.len(), 1);
    }
}

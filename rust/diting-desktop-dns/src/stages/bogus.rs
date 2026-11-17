//! Bogus NXDOMAIN correction.
//!
//! Some networks answer a nonexistent name with a navigation page instead of NXDOMAIN. The
//! configured address set identifies those pages. Rewriting to NXDOMAIN must happen after the cache
//! (so the correction is what gets cached) and before the response leaves the pipeline.

use async_trait::async_trait;
use diting_desktop_core::filter::RuleEngine;
use diting_dns_wire::build::ParsedMessage;

use crate::context::{DnsContext, RCODE_NXDOMAIN};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{attr_is_true, respond, start_reply};

pub struct BogusNxDomainStage {
    engine: RuleEngine,
}

impl BogusNxDomainStage {
    pub fn new(engine: RuleEngine) -> Self {
        Self { engine }
    }
}

#[async_trait]
impl Stage for BogusNxDomainStage {
    fn name(&self) -> &'static str {
        "bogus_nxdomain"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        if attr_is_true(ctx, "filter_blocked") {
            return;
        }
        let Some(response) = ctx.response.as_ref() else {
            return;
        };
        let Some(message) = ParsedMessage::parse(response) else {
            return;
        };
        if message.rcode() != 0 {
            return;
        }
        let addresses: Vec<std::net::IpAddr> = message
            .answers
            .iter()
            .filter_map(|record| match &record.rdata {
                diting_dns_wire::build::RData::A(ip) => Some(std::net::IpAddr::V4(*ip)),
                diting_dns_wire::build::RData::Aaaa(ip) => Some(std::net::IpAddr::V6(*ip)),
                _ => None,
            })
            .collect();
        let Some(hit) = self.engine.bogus_nxdomain(&addresses) else {
            return;
        };
        // Keep the answer type for the log by building a fresh NXDOMAIN; the question is unchanged.
        let Some(builder) = start_reply(ctx) else {
            return;
        };
        respond(ctx, builder.set_rcode(RCODE_NXDOMAIN));
        ctx.set("bogus_nxdomain", "true");
        ctx.set("filter_action", "block");
        ctx.set("filter_blocked", "true");
        ctx.set(
            "filter_reason",
            format!(
                "伪应答纠正: {} 解析为 {}，判定为上游劫持",
                ctx.question.name, hit.ip
            ),
        );
        ctx.set("filter_list", "bogus-nxdomain");
    }
}

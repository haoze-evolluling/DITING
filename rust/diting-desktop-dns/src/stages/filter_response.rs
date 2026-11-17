//! Response-side alias-chain recheck.
//!
//! A CNAME can point a harmless name at a blocked one; checking only the question name misses it.
//! The stage runs after the cache (so a cached answer is rechecked too), skips locally authoritative
//! answers, and evicts the poisoned entry from the cache.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::cache::DesktopCache;
use diting_desktop_core::filter::RuleEngine;
use diting_dns_wire::build::ParsedMessage;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::block::respond_blocked;
use crate::stages::records::response_records;
use crate::stages::util::{attr_is_true, normalized_name};

pub struct FilterResponseStage {
    engine: RuleEngine,
    cache: Option<Arc<DesktopCache>>,
}

impl FilterResponseStage {
    pub fn new(engine: RuleEngine) -> Self {
        Self { engine, cache: None }
    }

    pub fn with_cache(mut self, cache: Arc<DesktopCache>) -> Self {
        self.cache = Some(cache);
        self
    }
}

#[async_trait]
impl Stage for FilterResponseStage {
    fn name(&self) -> &'static str {
        "filter_response"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        if !self.engine.is_enabled() || !self.engine.filter_response_enabled() {
            return;
        }
        if attr_is_true(ctx, "filter_blocked") {
            return;
        }
        if matches!(
            ctx.get("source"),
            Some("hosts")
                | Some("rewrite")
                | Some("sudn")
                | Some("sudn_ddr")
                | Some("locally_served_zone")
        ) {
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
        let qname = normalized_name(&ctx.question.name);
        let records = response_records(&message);
        let verdict = self
            .engine
            .check_response(&qname, ctx.question.qtype, &ctx.group, &records);
        if !verdict.blocked {
            return;
        }
        let policy = self.engine.block_response_config(&ctx.group);
        respond_blocked(ctx, &policy);
        ctx.set("filter_action", "block");
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", &verdict.matched_rule);
        ctx.set("filter_reason", &verdict.reason);
        ctx.set("filter_list", &verdict.list_name);
        ctx.set("response_filtered", "true");
        if let Some(cache) = &self.cache {
            if let Some(key) = cache.key_for(&ctx.request, &ctx.group) {
                cache.raw().remove_keyed(&key);
            }
        }
    }
}

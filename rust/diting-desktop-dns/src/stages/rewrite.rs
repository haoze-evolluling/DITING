use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::rewrite::RewriteEngine;
use diting_dns_wire::build::{RData, ResourceRecord, TYPE_PTR};
use diting_dns_wire::CLASS_IN;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::private_ptr::parse_ptr_ip;
use crate::stages::records::to_wire_rdata;
use crate::stages::util::{normalized_name, respond, start_reply};

pub struct RewriteStage {
    engine: Arc<RewriteEngine>,
}

impl RewriteStage {
    pub fn new(engine: Arc<RewriteEngine>) -> Self {
        Self { engine }
    }
}

#[async_trait]
impl Stage for RewriteStage {
    fn name(&self) -> &'static str {
        "rewrite"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.engine.enabled() {
            return StageResult::Continue;
        }
        if ctx.question.qtype == TYPE_PTR {
            return self.answer_ptr(ctx);
        }
        let domain = normalized_name(&ctx.question.name);
        if domain.is_empty() {
            return StageResult::Continue;
        }
        let result = self.engine.lookup(&domain, ctx.question.qtype);
        if !result.matched {
            return StageResult::Continue;
        }
        let Some(mut builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        builder = builder.set_rcode(result.rcode.min(255) as u8);
        if result.rcode == 0 {
            for answer in &result.answers {
                builder = builder.push_answer(ResourceRecord::new(
                    answer.owner.clone(),
                    answer.record.rrtype(),
                    CLASS_IN,
                    answer.ttl,
                    to_wire_rdata(&answer.record),
                ));
            }
        }
        let nodata = result.rcode == 0 && result.answers.is_empty();
        respond(ctx, builder);
        ctx.set("source", "rewrite");
        ctx.set(
            "cache_hit",
            if result.rcode != 0 {
                "rewrite_rcode"
            } else if nodata {
                "rewrite_nodata"
            } else {
                "rewrite"
            },
        );
        StageResult::Stop
    }
}

impl RewriteStage {
    fn answer_ptr(&self, ctx: &mut DnsContext) -> StageResult {
        let Some(ip) = parse_ptr_ip(&ctx.question.name) else {
            return StageResult::Continue;
        };
        let names = self.engine.lookup_ptr(ip);
        if names.is_empty() {
            return StageResult::Continue;
        }
        let Some(mut builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        for name in names {
            builder = builder.push_answer(ResourceRecord::new(
                &ctx.question.name,
                TYPE_PTR,
                CLASS_IN,
                diting_desktop_api::config::rewrite_zone::DEFAULT_REWRITE_TTL,
                RData::Ptr(crate::stages::util::normalize_trailing_dot(&name)),
            ));
        }
        respond(ctx, builder);
        ctx.set("source", "rewrite");
        ctx.set("cache_hit", "rewrite");
        StageResult::Stop
    }
}

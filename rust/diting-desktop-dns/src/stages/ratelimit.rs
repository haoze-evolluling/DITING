//! Per-client query rate limiting.
//!
//! A refused query is marked `ratelimit_blocked` so EDE explains it as Prohibited rather than as a
//! generic access denial.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::ratelimit::RateLimiter;

use crate::context::{DnsContext, RCODE_REFUSED};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{respond, start_reply};

pub struct RateLimitStage {
    limiter: Arc<RateLimiter>,
}

impl RateLimitStage {
    pub fn new(limiter: Arc<RateLimiter>) -> Self {
        Self { limiter }
    }
}

#[async_trait]
impl Stage for RateLimitStage {
    fn name(&self) -> &'static str {
        "ratelimit"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.limiter.enabled() {
            return StageResult::Continue;
        }
        let ip = ctx.client.map(|address| address.ip());
        if self.limiter.allow(ip) {
            return StageResult::Continue;
        }
        let Some(builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        respond(ctx, builder.set_rcode(RCODE_REFUSED));
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", "RATE_LIMIT_EXCEEDED");
        ctx.set("filter_reason", "Client query rate limit exceeded");
        ctx.set("ratelimit_blocked", "true");
        StageResult::Stop
    }
}

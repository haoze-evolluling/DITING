//! Client access control.
//!
//! The blocked list wins over the allow list; a non-empty allow list means everything else is
//! refused. Refused queries carry the marker EDE reads so the client learns "prohibited" rather
//! than a bare REFUSED.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::access::AccessControl;

use crate::context::{DnsContext, RCODE_REFUSED};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{respond, start_reply};

pub struct AccessStage {
    access: Arc<AccessControl>,
}

impl AccessStage {
    pub fn new(access: Arc<AccessControl>) -> Self {
        Self { access }
    }
}

#[async_trait]
impl Stage for AccessStage {
    fn name(&self) -> &'static str {
        "access"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let ip = ctx.client.map(|address| address.ip());
        let (allowed, reason) = self.access.check(ip);
        if allowed {
            return StageResult::Continue;
        }
        let Some(builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        respond(ctx, builder.set_rcode(RCODE_REFUSED));
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", "CLIENT_ACCESS_CONTROL");
        ctx.set("filter_reason", reason);
        ctx.set("access_blocked", "true");
        StageResult::Stop
    }
}

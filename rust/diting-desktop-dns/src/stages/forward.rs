//! Terminal upstream forwarding.
//!
//! `DesktopResolver` has already applied the conditional route, the client group's dedicated
//! upstreams and the fallback chain. This stage only turns a transport failure into SERVFAIL so the
//! client never hangs, and records the error for EDE and the query log.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::resolver::DesktopResolver;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};

pub struct ForwardStage {
    resolver: Arc<DesktopResolver>,
}

impl ForwardStage {
    pub fn new(resolver: Arc<DesktopResolver>) -> Self {
        Self { resolver }
    }
}

#[async_trait]
impl Stage for ForwardStage {
    fn name(&self) -> &'static str {
        "forward"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        match self.resolver.resolve(&ctx.request, &ctx.group).await {
            Ok(response) => {
                ctx.error = None;
                ctx.response = Some(response);
            }
            Err(error) => {
                ctx.error = Some(error);
                ctx.fail_servfail();
            }
        }
        StageResult::Stop
    }
}

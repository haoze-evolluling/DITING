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
        match self
            .resolver
            .resolve_attributed(&ctx.request, &ctx.group)
            .await
        {
            (Ok(response), provider) => {
                if let Some(provider) = provider {
                    ctx.set("upstream_provider", provider);
                }
                ctx.error = None;
                ctx.response = Some(response);
            }
            (Err(error), provider) => {
                if let Some(provider) = provider {
                    ctx.set("upstream_provider", provider);
                }
                ctx.error = Some(error);
                ctx.fail_servfail();
            }
        }
        StageResult::Stop
    }
}

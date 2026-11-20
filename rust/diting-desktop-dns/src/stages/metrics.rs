use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::metrics::MetricsTracker;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};

pub trait QueryObserver: Send + Sync {
    fn observe(&self, ctx: &DnsContext);
}

pub struct MetricsStage {
    tracker: Arc<MetricsTracker>,
    observer: Option<Arc<dyn QueryObserver>>,
}

impl MetricsStage {
    pub fn new(tracker: Arc<MetricsTracker>, observer: Option<Arc<dyn QueryObserver>>) -> Self {
        Self { tracker, observer }
    }
}

#[async_trait]
impl Stage for MetricsStage {
    fn name(&self) -> &'static str {
        "metrics"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        let failed = ctx.error.is_some()
            || ctx
                .response
                .as_ref()
                .and_then(|wire| diting_dns_wire::parse_header(wire))
                .map(|header| header.flags & 0x000f == 2)
                .unwrap_or(true);
        self.tracker.record_query(ctx.started.elapsed(), !failed);
        if let Some(observer) = &self.observer {
            observer.observe(ctx);
        }
    }
}

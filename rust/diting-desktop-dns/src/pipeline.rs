//! The fixed middleware chain.
//!
//! The Go service registered an onion: each middleware ran its prelude, called `next`, then its
//! postlude. The order is part of the product behaviour (a cache key must see the client group, an
//! EDE stage must decorate whatever the cache or upstream produced), so this Rust port keeps the
//! same names and order and runs every stage's `after` in reverse after the forward walk stops.
//!
//! A stage can stop the walk (block page, local answer, rate limit). Stages already entered still
//! get their postlude, which is how metrics observes a blocked query and ECH strips a cached
//! response.

use std::sync::Arc;

use async_trait::async_trait;

use crate::context::DnsContext;

/// Every stage, in registration order. Tests assert the pipeline is assembled in this order.
pub const PIPELINE_ORDER: &[&str] = &[
    "metrics",
    "ede",
    "ech",
    "client",
    "access",
    "ratelimit",
    "ddr",
    "sudn",
    "zone",
    "hosts",
    "rewrite",
    "safesearch",
    "ipv6",
    "private_ptr",
    "unqualified",
    "any",
    "filter",
    "safebrowsing",
    "rebind",
    "filter_response",
    "dns64",
    "ecs",
    "cache",
    "bogus_nxdomain",
    "upstream_route",
    "forward",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StageResult {
    Continue,
    /// The stage produced the final response (or decided to drop the query).
    Stop,
    /// The stage failed; the pipeline records the error and stops, then synthesizes SERVFAIL.
    Fail(String),
}

#[async_trait]
pub trait Stage: Send + Sync {
    fn name(&self) -> &'static str;
    async fn before(&self, ctx: &mut DnsContext) -> StageResult;
    /// Runs in reverse order after the forward walk. Must tolerate a missing response.
    async fn after(&self, _ctx: &mut DnsContext) {}
}

pub struct Pipeline {
    stages: Vec<Arc<dyn Stage>>,
}

impl Pipeline {
    pub fn new(stages: Vec<Arc<dyn Stage>>) -> Self {
        Self { stages }
    }

    pub fn stage_names(&self) -> Vec<&'static str> {
        self.stages.iter().map(|stage| stage.name()).collect()
    }

    pub async fn execute(&self, ctx: &mut DnsContext) {
        let mut entered = Vec::with_capacity(self.stages.len());
        for stage in &self.stages {
            entered.push(stage.clone());
            match stage.before(ctx).await {
                StageResult::Continue => continue,
                StageResult::Stop => break,
                StageResult::Fail(error) => {
                    ctx.error = Some(error);
                    break;
                }
            }
        }
        for stage in entered.into_iter().rev() {
            stage.after(ctx).await;
        }
        if ctx.response.is_none() {
            ctx.fail_servfail();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct Recorder {
        name: &'static str,
        log: Arc<Mutex<Vec<String>>>,
        stop: bool,
    }

    #[async_trait]
    impl Stage for Recorder {
        fn name(&self) -> &'static str {
            self.name
        }

        async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
            self.log
                .lock()
                .unwrap()
                .push(format!("{}:before", self.name));
            if self.stop {
                StageResult::Stop
            } else {
                StageResult::Continue
            }
        }

        async fn after(&self, _ctx: &mut DnsContext) {
            self.log
                .lock()
                .unwrap()
                .push(format!("{}:after", self.name));
        }
    }

    fn context() -> DnsContext {
        let query = diting_dns_wire::build::MessageBuilder::query("example.com", 1, 1)
            .finish()
            .unwrap();
        DnsContext::new(query, None, crate::context::Transport::Udp).unwrap()
    }

    #[tokio::test]
    async fn postludes_run_in_reverse_and_stopping_stage_gets_one() {
        let log = Arc::new(Mutex::new(Vec::new()));
        let pipeline = Pipeline::new(vec![
            Arc::new(Recorder {
                name: "a",
                log: log.clone(),
                stop: false,
            }),
            Arc::new(Recorder {
                name: "b",
                log: log.clone(),
                stop: true,
            }),
            Arc::new(Recorder {
                name: "c",
                log: log.clone(),
                stop: false,
            }),
        ]);
        let mut ctx = context();
        pipeline.execute(&mut ctx).await;
        assert_eq!(
            *log.lock().unwrap(),
            vec!["a:before", "b:before", "b:after", "a:after"]
        );
        // No stage answered, so the pipeline must not leave the client hanging.
        assert!(ctx.response.is_some());
    }
}

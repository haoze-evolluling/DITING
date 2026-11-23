use std::sync::Arc;

use async_trait::async_trait;

use crate::context::DnsContext;


#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StageResult {
    Continue,
    Stop,
    Fail(String),
}

#[async_trait]
pub trait Stage: Send + Sync {
    fn name(&self) -> &'static str;
    async fn before(&self, ctx: &mut DnsContext) -> StageResult;
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
        assert!(ctx.response.is_some());
    }
}

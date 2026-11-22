use std::sync::Arc;
use std::time::Duration;

use crate::AppRuntime;

const PREFETCH_TICK: Duration = Duration::from_secs(5);

const PERSIST_IDLE_RECHECK: Duration = Duration::from_secs(30);

const MIN_PERSIST_INTERVAL_SECONDS: i64 = 10;

pub struct Maintenance {
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

impl Maintenance {
    pub fn spawn(runtime: Arc<AppRuntime>) -> Self {
        let tasks = vec![
            tokio::spawn(prefetch_loop(Arc::clone(&runtime))),
            tokio::spawn(persist_loop(runtime)),
        ];
        Self { tasks }
    }

    pub async fn shutdown(mut self) {
        for task in self.tasks.drain(..) {
            task.abort();
        }
    }
}

async fn prefetch_loop(runtime: Arc<AppRuntime>) {
    let mut ticker = tokio::time::interval(PREFETCH_TICK);
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        ticker.tick().await;
        runtime.cache.prefetch(&runtime.resolver).await;
    }
}

async fn persist_loop(runtime: Arc<AppRuntime>) {
    loop {
        let config = runtime.config();
        if !config.cache.persist_enabled {
            tokio::time::sleep(PERSIST_IDLE_RECHECK).await;
            continue;
        }
        let seconds = config.cache.persist_interval_seconds;
        if seconds <= 0 {
            tokio::time::sleep(PERSIST_IDLE_RECHECK).await;
            continue;
        }
        let interval = Duration::from_secs(seconds.max(MIN_PERSIST_INTERVAL_SECONDS) as u64);
        tokio::time::sleep(interval).await;
        let _ = runtime.save_cache();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_api::config::Config;

    #[tokio::test(start_paused = true)]
    async fn persist_loop_writes_after_interval() {
        let mut config = Config::default();
        config.cache.persist_enabled = true;
        config.cache.persist_interval_seconds = 60;
        let dir = std::env::temp_dir().join(format!(
            "diting-maint-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        config.cache.persist_path = dir.join("cache.json").to_string_lossy().to_string();

        let runtime = Arc::new(AppRuntime::new(config));
        let maintenance = Maintenance::spawn(Arc::clone(&runtime));
        tokio::time::sleep(Duration::from_secs(61)).await;
        assert!(std::path::Path::new(&runtime.config().cache.persist_path).exists());
        maintenance.shutdown().await;
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test(start_paused = true)]
    async fn prefetch_tick_is_a_no_op_when_disabled() {
        let runtime = Arc::new(AppRuntime::new(Config::default()));
        assert!(!runtime.config().cache.prefetch_enabled);
        let maintenance = Maintenance::spawn(Arc::clone(&runtime));
        tokio::time::sleep(Duration::from_secs(11)).await;
        assert_eq!(runtime.cache.metrics().prefetch_count, 0);
        maintenance.shutdown().await;
    }
}

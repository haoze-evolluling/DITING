//! Background upkeep that is not part of any request path.
//!
//! Go ran three independent goroutines for this: a fixed 3s metrics ticker (owned by the IPC layer),
//! a hot-entry prefetch sweep and the cache persistence loop. The rules engine starts its own list
//! refresh ticker, so only the latter two live here. Both loops re-read the configuration on every
//! wake-up, which keeps them correct across live configuration changes without a restart.

use std::sync::Arc;
use std::time::Duration;

use crate::AppRuntime;

/// How often the cache looks for hot entries that are about to expire.
///
/// The sweep is cheap (it only exports keys and TTLs) and internally throttles each key to one
/// refresh per [`diting_desktop_core::cache`] `PREFETCH_MIN_INTERVAL_MS`, so a short tick does not
/// multiply upstream traffic.
const PREFETCH_TICK: Duration = Duration::from_secs(5);

/// Re-check interval while periodic persistence is disabled, so enabling it later takes effect
/// without restarting the service.
const PERSIST_IDLE_RECHECK: Duration = Duration::from_secs(30);

/// Guard against a hand-edited interval of one second turning persistence into a hot loop.
const MIN_PERSIST_INTERVAL_SECONDS: i64 = 10;

/// Owns the background tasks and stops them on shutdown.
pub struct Maintenance {
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

impl Maintenance {
    /// Starts the upkeep tasks. The runtime must outlive them.
    pub fn spawn(runtime: Arc<AppRuntime>) -> Self {
        let tasks = vec![
            tokio::spawn(prefetch_loop(Arc::clone(&runtime))),
            tokio::spawn(persist_loop(runtime)),
        ];
        Self { tasks }
    }

    /// Stops every task. A task interrupted mid-write is safe: persistence writes a temporary
    /// file and renames it, so a partial file never replaces the previous snapshot.
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
            // Configured without a periodic interval: Go only wrote on shutdown, which
            // `AppRuntime::save_cache` still does from the service's own exit path.
            tokio::time::sleep(PERSIST_IDLE_RECHECK).await;
            continue;
        }
        let interval = Duration::from_secs(seconds.max(MIN_PERSIST_INTERVAL_SECONDS) as u64);
        tokio::time::sleep(interval).await;
        // A failed write leaves the in-memory cache untouched and is surfaced through the
        // persistence status endpoint, so there is nothing to do here but try again next round.
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
        // One interval plus a little slack for the task to observe its wake-up.
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

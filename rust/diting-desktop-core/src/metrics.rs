use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct MetricsSnapshot {
    pub total_queries: u64,
    pub success_queries: u64,
    pub failed_queries: u64,
    pub avg_latency_ms: f64,
    pub qps: f64,
}

pub struct MetricsTracker {
    started: Instant,
    total: AtomicU64,
    success: AtomicU64,
    failed: AtomicU64,
    total_latency_ns: AtomicU64,
}

impl MetricsTracker {
    pub fn new() -> Self {
        Self {
            started: Instant::now(),
            total: AtomicU64::new(0),
            success: AtomicU64::new(0),
            failed: AtomicU64::new(0),
            total_latency_ns: AtomicU64::new(0),
        }
    }

    pub fn record_query(&self, duration: Duration, success: bool) {
        self.total.fetch_add(1, Ordering::Relaxed);
        if success {
            self.success.fetch_add(1, Ordering::Relaxed);
        } else {
            self.failed.fetch_add(1, Ordering::Relaxed);
        }
        self.total_latency_ns.fetch_add(
            duration.as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
    }

    pub fn uptime_seconds(&self) -> i64 {
        self.started.elapsed().as_secs() as i64
    }

    pub fn snapshot(&self) -> MetricsSnapshot {
        let total = self.total.load(Ordering::Relaxed);
        let success = self.success.load(Ordering::Relaxed);
        let failed = self.failed.load(Ordering::Relaxed);
        let total_ns = self.total_latency_ns.load(Ordering::Relaxed);

        let avg_latency_ms = if total > 0 {
            total_ns as f64 / total as f64 / 1e6
        } else {
            0.0
        };
        let uptime = self.started.elapsed().as_secs_f64();
        let qps = if uptime > 0.0 {
            total as f64 / uptime
        } else {
            0.0
        };

        MetricsSnapshot {
            total_queries: total,
            success_queries: success,
            failed_queries: failed,
            avg_latency_ms,
            qps,
        }
    }
}

impl Default for MetricsTracker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counters_and_rates() {
        let tracker = MetricsTracker::new();
        tracker.record_query(Duration::from_millis(10), true);
        tracker.record_query(Duration::from_millis(30), false);
        let snapshot = tracker.snapshot();
        assert_eq!(snapshot.total_queries, 2);
        assert_eq!(snapshot.success_queries, 1);
        assert_eq!(snapshot.failed_queries, 1);
        assert!((snapshot.avg_latency_ms - 20.0).abs() < 0.001);
        assert!(snapshot.qps >= 0.0);
    }
}

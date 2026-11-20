use std::collections::HashMap;
use std::sync::Mutex;

pub const FLUSH_THRESHOLD_BYTES: i64 = 1024 * 1024;
pub const MAX_BUFFERED_BYTES: i64 = 8 * 1024 * 1024;
pub const MIN_BACKOFF_MS: i64 = 2_000;
pub const MAX_BACKOFF_MS: i64 = 60_000;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct TickRow {
    pub uid: i32,
    pub tx: i64,
    pub rx: i64,
    pub package: String,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Delta {
    pub tx: i64,
    pub rx: i64,
}

impl Delta {
    fn total(self) -> i64 {
        self.tx.wrapping_add(self.rx)
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct TickOutcome {
    pub flush: bool,
    pub tick_tx: i64,
    pub tick_rx: i64,
    pub dropped_date: Option<String>,
    pub dropped_packages: u32,
}

pub type Bucket = Vec<(String, Delta)>;

#[derive(Debug, Default)]
struct Inner {
    buckets: Vec<(String, HashMap<String, Delta>)>,
    buffered_bytes: i64,
    backoff_ms: i64,
    retry_at_ms: i64,
}

#[derive(Debug, Default)]
pub struct Traffic {
    inner: Mutex<Inner>,
}

impl Traffic {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn on_tick(&self, today: &str, rows: &[TickRow]) -> TickOutcome {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let mut outcome = TickOutcome::default();
        let position = match inner.buckets.iter().position(|(date, _)| date == today) {
            Some(position) => position,
            None => {
                inner.buckets.push((today.to_string(), HashMap::new()));
                inner.buckets.len() - 1
            }
        };

        let mut added_bytes = 0i64;
        {
            let bucket = &mut inner.buckets[position].1;
            for row in rows {
                if row.uid <= 0 || (row.tx <= 0 && row.rx <= 0) {
                    continue;
                }
                outcome.tick_tx = outcome.tick_tx.wrapping_add(row.tx);
                outcome.tick_rx = outcome.tick_rx.wrapping_add(row.rx);
                if crate::row::is_blank(&row.package) {
                    continue;
                }
                let delta = bucket.entry(row.package.clone()).or_default();
                delta.tx = delta.tx.wrapping_add(row.tx);
                delta.rx = delta.rx.wrapping_add(row.rx);
                added_bytes = added_bytes.wrapping_add(row.tx).wrapping_add(row.rx);
            }
        }

        inner.buffered_bytes = inner.buffered_bytes.wrapping_add(added_bytes);
        outcome.flush = inner.buffered_bytes > FLUSH_THRESHOLD_BYTES;
        if inner.buffered_bytes > MAX_BUFFERED_BYTES && inner.buckets.len() > 1 {
            let (date, dropped) = inner.buckets.remove(0);
            let dropped_bytes = dropped
                .values()
                .map(|delta| delta.total())
                .fold(0i64, |sum, value| sum.wrapping_add(value));
            inner.buffered_bytes = inner.buffered_bytes.wrapping_sub(dropped_bytes);
            outcome.dropped_packages = dropped.len() as u32;
            outcome.dropped_date = Some(date);
        }
        outcome
    }

    pub fn take(&self) -> Vec<(String, Bucket)> {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let drained = inner
            .buckets
            .drain(..)
            .map(|(date, bucket)| {
                let rows: Bucket = bucket.into_iter().collect();
                (date, rows)
            })
            .collect();
        inner.buffered_bytes = 0;
        drained
    }

    pub fn requeue(&self, failed: Vec<(String, Bucket)>) {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let mut added_bytes = 0i64;
        for (date, bucket) in failed {
            let position = match inner
                .buckets
                .iter()
                .position(|(existing, _)| *existing == date)
            {
                Some(position) => position,
                None => {
                    inner.buckets.push((date, HashMap::new()));
                    inner.buckets.len() - 1
                }
            };
            let target = &mut inner.buckets[position].1;
            for (package, delta) in bucket {
                let merged = target.entry(package).or_default();
                merged.tx = merged.tx.wrapping_add(delta.tx);
                merged.rx = merged.rx.wrapping_add(delta.rx);
                added_bytes = added_bytes.wrapping_add(delta.total());
            }
        }
        inner.buffered_bytes = inner.buffered_bytes.wrapping_add(added_bytes);
    }

    pub fn clear(&self) -> u32 {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let remaining: usize = inner.buckets.iter().map(|(_, bucket)| bucket.len()).sum();
        inner.buckets.clear();
        inner.buffered_bytes = 0;
        remaining as u32
    }

    pub fn backoff(&self, now_ms: i64) -> i64 {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.backoff_ms = if inner.backoff_ms <= 0 {
            MIN_BACKOFF_MS
        } else {
            inner.backoff_ms.saturating_mul(2).min(MAX_BACKOFF_MS)
        };
        inner.retry_at_ms = now_ms.saturating_add(inner.backoff_ms);
        inner.backoff_ms
    }

    pub fn reset_backoff(&self) {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.backoff_ms = 0;
        inner.retry_at_ms = 0;
    }

    pub fn in_backoff(&self, now_ms: i64) -> bool {
        now_ms
            < self
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .retry_at_ms
    }

    pub fn buffered_bytes(&self) -> i64 {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .buffered_bytes
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(uid: i32, tx: i64, rx: i64, package: &str) -> TickRow {
        TickRow {
            uid,
            tx,
            rx,
            package: package.to_string(),
        }
    }

    #[test]
    fn deltas_bucket_by_date_and_package() {
        let traffic = Traffic::new();
        let outcome = traffic.on_tick(
            "2026-01-01",
            &[
                row(10001, 100, 200, "com.a"),
                row(10002, 10, 0, "com.b"),
                row(10003, 5, 5, ""),
                row(0, 100, 100, "com.c"),
                row(10004, 0, 0, "com.d"),
                row(10005, -1, 0, "com.e"),
            ],
        );
        assert_eq!((outcome.tick_tx, outcome.tick_rx), (115, 205));
        assert!(!outcome.flush);
        assert_eq!(outcome.dropped_date, None);

        let taken = traffic.take();
        assert_eq!(taken.len(), 1);
        let (date, bucket) = &taken[0];
        assert_eq!(date, "2026-01-01");
        let mut sorted = bucket.clone();
        sorted.sort_by(|left, right| left.0.cmp(&right.0));
        assert_eq!(
            sorted,
            vec![
                ("com.a".to_string(), Delta { tx: 100, rx: 200 }),
                ("com.b".to_string(), Delta { tx: 10, rx: 0 }),
            ]
        );
        assert_eq!(traffic.buffered_bytes(), 0);
        assert!(traffic.take().is_empty());
    }

    #[test]
    fn a_second_tick_merges_into_the_same_package() {
        let traffic = Traffic::new();
        traffic.on_tick("2026-01-01", &[row(1, 10, 10, "com.a")]);
        traffic.on_tick("2026-01-01", &[row(1, 5, 7, "com.a")]);
        let taken = traffic.take();
        assert_eq!(
            taken[0].1,
            vec![("com.a".to_string(), Delta { tx: 15, rx: 17 })]
        );
    }

    #[test]
    fn the_flush_threshold_is_strictly_greater() {
        let traffic = Traffic::new();
        let chunk = FLUSH_THRESHOLD_BYTES / 2;
        assert!(!traffic.on_tick("d", &[row(1, chunk, 0, "com.a")]).flush);
        assert!(!traffic.on_tick("d", &[row(1, chunk, 0, "com.a")]).flush);
        assert!(traffic.on_tick("d", &[row(1, 1, 0, "com.a")]).flush);
    }

    #[test]
    fn overflow_drops_the_oldest_date_and_keeps_the_newest() {
        let traffic = Traffic::new();
        let chunk = MAX_BUFFERED_BYTES / 2;
        traffic.on_tick(
            "2026-01-01",
            &[row(1, chunk, 0, "com.a"), row(2, 0, 0, "com.b")],
        );
        let outcome = traffic.on_tick("2026-01-02", &[row(3, chunk, 1, "com.c")]);
        assert_eq!(outcome.dropped_date.as_deref(), Some("2026-01-01"));
        assert_eq!(outcome.dropped_packages, 1);
        let taken = traffic.take();
        assert_eq!(taken.len(), 1);
        assert_eq!(taken[0].0, "2026-01-02");
        assert_eq!(
            taken[0].1,
            vec![("com.c".to_string(), Delta { tx: chunk, rx: 1 })]
        );
    }

    #[test]
    fn a_single_date_bucket_is_never_dropped() {
        let traffic = Traffic::new();
        let chunk = MAX_BUFFERED_BYTES / 2;
        traffic.on_tick("d", &[row(1, chunk, 0, "com.a")]);
        let outcome = traffic.on_tick("d", &[row(1, chunk, 0, "com.b")]);
        assert_eq!(outcome.dropped_date, None);
        assert_eq!(traffic.take()[0].1.len(), 2);
    }

    #[test]
    fn requeue_merges_back_under_the_original_date() {
        let traffic = Traffic::new();
        traffic.on_tick("2026-01-01", &[row(1, 10, 10, "com.a")]);
        let taken = traffic.take();
        assert_eq!(traffic.buffered_bytes(), 0);
        traffic.on_tick("2026-01-01", &[row(1, 1, 1, "com.a")]);
        traffic.requeue(taken);
        assert_eq!(traffic.buffered_bytes(), 22);
        let taken = traffic.take();
        assert_eq!(taken.len(), 1);
        assert_eq!(
            taken[0].1,
            vec![("com.a".to_string(), Delta { tx: 11, rx: 11 })]
        );
    }

    #[test]
    fn a_failed_write_backs_off_from_two_seconds_to_a_minute() {
        let traffic = Traffic::new();
        assert!(!traffic.in_backoff(0));
        assert_eq!(traffic.backoff(1_000), MIN_BACKOFF_MS);
        assert!(traffic.in_backoff(2_999));
        assert!(!traffic.in_backoff(3_000));
        assert_eq!(traffic.backoff(3_000), 4_000);
        for now in [10_000, 20_000, 40_000, 80_000] {
            traffic.backoff(now);
        }
        assert_eq!(traffic.backoff(90_000), MAX_BACKOFF_MS);
        traffic.reset_backoff();
        assert!(!traffic.in_backoff(90_000));
        assert_eq!(traffic.backoff(100_000), MIN_BACKOFF_MS);
    }

    #[test]
    fn clear_reports_the_lost_rows() {
        let traffic = Traffic::new();
        traffic.on_tick("d", &[row(1, 1, 1, "com.a"), row(2, 1, 1, "com.b")]);
        traffic.on_tick("d2", &[row(3, 1, 1, "com.c")]);
        assert_eq!(traffic.clear(), 3);
        assert!(traffic.take().is_empty());
    }
}

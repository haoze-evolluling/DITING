//! The writer queues behind `LogTableWriter` and `HttpRequestLogWriter`: a bounded `VecDeque` of
//! packed rows plus the policy around it (when a batch is worth writing, what to drop when the
//! database stays busy, how long to back off).
//!
//! The SQL, the compiled statements, the `ContentValues` and the timers stay in Kotlin; what moves
//! here is every number and every ordering decision, so the four tables and the HTTP writer cannot
//! end up with four different ideas of "full".

use std::collections::VecDeque;
use std::sync::Mutex;

/// One writer's queue parameters (`LogTableWriter.MAX_PENDING_ROWS` and friends, or
/// `HttpRequestLogWriter`'s batch of ten).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    /// Queue length that flushes immediately instead of waiting for the timer.
    pub batch_size: usize,
    /// Timer for a queue that has not reached `batch_size`.
    pub flush_interval_ms: i64,
    /// Hard cap: past it the oldest rows are dropped, so a stuck database cannot grow the heap.
    pub max_pending: usize,
    /// Rows one transaction may take; a flush that returns them all loops again.
    pub max_per_transaction: usize,
    /// First backoff after a failed write, doubled up to `max_backoff_ms`.
    pub min_backoff_ms: i64,
    pub max_backoff_ms: i64,
    /// How long a confirmed-missing table drops rows without asking again; 0 disables the latch.
    pub missing_recheck_ms: i64,
}

/// `LogTableWriter`'s numbers: 200 rows or 1 s, 10k queued, 500 per transaction, 1 s → 30 s backoff,
/// and a 30 s re-check after a table was found missing.
pub const LOG_TABLE: Settings = Settings {
    batch_size: 200,
    flush_interval_ms: 1_000,
    max_pending: 10_000,
    max_per_transaction: 500,
    min_backoff_ms: 1_000,
    max_backoff_ms: 30_000,
    missing_recheck_ms: 30_000,
};

/// `HttpRequestLogWriter`'s numbers: 10 rows or 500 ms, 5k queued, one transaction per flush,
/// 2 s → 30 s backoff, and no missing-table latch (the mode filter already bounds the volume).
pub const HTTP: Settings = Settings {
    batch_size: 10,
    flush_interval_ms: 500,
    max_pending: 5_000,
    max_per_transaction: 5_000,
    min_backoff_ms: 2_000,
    max_backoff_ms: 30_000,
    missing_recheck_ms: 0,
};

/// What one `submit` decided.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Submit {
    /// Rows dropped off the front to stay under `max_pending`.
    pub overflow: u32,
    /// The queue reached `batch_size`, so the timer should fire now.
    pub batch_full: bool,
}

impl Submit {
    /// The delay the caller should schedule its drain with.
    pub fn flush_delay_ms(self, settings: Settings) -> i64 {
        if self.batch_full {
            0
        } else {
            settings.flush_interval_ms
        }
    }
}

#[derive(Debug)]
struct Inner {
    pending: VecDeque<Vec<u8>>,
    closed: bool,
    backoff_ms: i64,
    retry_at_ms: i64,
    missing_until_ms: i64,
}

/// One writer's queue.
#[derive(Debug)]
pub struct Queue {
    settings: Settings,
    inner: Mutex<Inner>,
}

impl Queue {
    pub fn new(settings: Settings) -> Self {
        Self {
            settings,
            inner: Mutex::new(Inner {
                pending: VecDeque::new(),
                closed: false,
                backoff_ms: 0,
                retry_at_ms: 0,
                missing_until_ms: 0,
            }),
        }
    }

    pub fn settings(&self) -> Settings {
        self.settings
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|error| error.into_inner())
    }

    /// `submit`: None once the writer is closed, otherwise the overflow and the flush decision.
    pub fn submit(&self, row: Vec<u8>, _now_ms: i64) -> Option<Submit> {
        let mut inner = self.lock();
        if inner.closed {
            return None;
        }
        inner.pending.push_back(row);
        let mut overflow = 0u32;
        while inner.pending.len() > self.settings.max_pending {
            inner.pending.pop_front();
            overflow = overflow.saturating_add(1);
        }
        Some(Submit {
            overflow,
            batch_full: inner.pending.len() >= self.settings.batch_size,
        })
    }

    /// `takeBatch`: at most `max_per_transaction` rows, oldest first; None when nothing is queued.
    pub fn take(&self) -> Option<Vec<Vec<u8>>> {
        let mut inner = self.lock();
        if inner.pending.is_empty() {
            return None;
        }
        let count = inner.pending.len().min(self.settings.max_per_transaction);
        Some(inner.pending.drain(..count).collect())
    }

    /// `requeue`: put an unwritten batch back in front so the queue stays chronological.
    pub fn requeue(&self, batch: Vec<Vec<u8>>) -> u32 {
        let mut inner = self.lock();
        for row in batch.into_iter().rev() {
            inner.pending.push_front(row);
        }
        let mut overflow = 0u32;
        while inner.pending.len() > self.settings.max_pending {
            inner.pending.pop_front();
            overflow = overflow.saturating_add(1);
        }
        overflow
    }

    /// `backoff`: grow the window (first 1 s, then doubling, capped) and report the new length.
    pub fn backoff(&self, now_ms: i64) -> i64 {
        let mut inner = self.lock();
        inner.backoff_ms = if inner.backoff_ms <= 0 {
            self.settings.min_backoff_ms
        } else {
            inner
                .backoff_ms
                .saturating_mul(2)
                .min(self.settings.max_backoff_ms)
        };
        inner.retry_at_ms = now_ms.saturating_add(inner.backoff_ms);
        inner.backoff_ms
    }

    pub fn reset_backoff(&self) {
        let mut inner = self.lock();
        inner.backoff_ms = 0;
        inner.retry_at_ms = 0;
    }

    /// How long the drain should wait before retrying; 0 means "now".
    pub fn retry_wait_ms(&self, now_ms: i64) -> i64 {
        let inner = self.lock();
        inner.retry_at_ms.saturating_sub(now_ms).max(0)
    }

    /// True when this call is still inside the backoff window.
    pub fn in_backoff(&self, now_ms: i64) -> bool {
        now_ms < self.lock().retry_at_ms
    }

    /// True while a confirmed-missing table drops rows without asking again.
    pub fn missing_latched(&self, now_ms: i64) -> bool {
        if self.settings.missing_recheck_ms == 0 {
            return false;
        }
        now_ms < self.lock().missing_until_ms
    }

    pub fn latch_missing(&self, now_ms: i64) {
        if self.settings.missing_recheck_ms == 0 {
            return;
        }
        let mut inner = self.lock();
        inner.missing_until_ms = now_ms.saturating_add(self.settings.missing_recheck_ms);
    }

    pub fn is_closed(&self) -> bool {
        self.lock().closed
    }

    /// Stop accepting rows but keep the queue, so `close` can still flush it.
    pub fn mark_closed(&self) {
        self.lock().closed = true;
    }

    /// `close`: stop accepting rows and report how many were still queued (the lost tail).
    pub fn close(&self) -> u32 {
        let mut inner = self.lock();
        inner.closed = true;
        let remaining = inner.pending.len() as u32;
        inner.pending.clear();
        remaining
    }

    pub fn pending_len(&self) -> u32 {
        self.lock().pending.len() as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(name: &str) -> Vec<u8> {
        name.as_bytes().to_vec()
    }

    fn names(batch: &[Vec<u8>]) -> Vec<String> {
        batch
            .iter()
            .map(|row| String::from_utf8_lossy(row).into_owned())
            .collect()
    }

    #[test]
    fn a_full_batch_flushes_now_and_a_small_one_waits_for_the_timer() {
        let queue = Queue::new(LOG_TABLE);
        for index in 0..(LOG_TABLE.batch_size - 1) {
            let submit = queue.submit(row(&index.to_string()), 0).unwrap();
            assert!(!submit.batch_full);
            assert_eq!(submit.flush_delay_ms(LOG_TABLE), 1_000);
        }
        let submit = queue.submit(row("last"), 0).unwrap();
        assert!(submit.batch_full);
        assert_eq!(submit.flush_delay_ms(LOG_TABLE), 0);
        assert_eq!(queue.pending_len(), LOG_TABLE.batch_size as u32);
    }

    #[test]
    fn the_http_writer_flushes_every_ten_rows() {
        let queue = Queue::new(HTTP);
        assert_eq!(queue.submit(row("1"), 0).unwrap().flush_delay_ms(HTTP), 500);
        for index in 2..10 {
            queue.submit(row(&index.to_string()), 0).unwrap();
        }
        assert_eq!(queue.submit(row("10"), 0).unwrap().flush_delay_ms(HTTP), 0);
    }

    #[test]
    fn past_the_cap_the_oldest_rows_are_dropped() {
        let queue = Queue::new(HTTP);
        for index in 0..HTTP.max_pending {
            assert_eq!(
                queue.submit(row(&index.to_string()), 0).unwrap().overflow,
                0
            );
        }
        let submit = queue.submit(row("newest"), 0).unwrap();
        assert_eq!(submit.overflow, 1);
        assert_eq!(queue.pending_len(), HTTP.max_pending as u32);
        let taken = queue.take().unwrap();
        // The oldest row is gone, the newest is in.
        assert_eq!(names(&taken)[0], "1");
        assert_eq!(names(&taken)[HTTP.max_pending - 1], "newest");
    }

    #[test]
    fn one_transaction_takes_a_chunk_and_the_rest_stays_queued() {
        let queue = Queue::new(LOG_TABLE);
        for index in 0..600 {
            queue.submit(row(&index.to_string()), 0);
        }
        let first = queue.take().unwrap();
        assert_eq!(first.len(), 500);
        assert_eq!(names(&first)[0], "0");
        assert_eq!(names(&first)[499], "499");
        let second = queue.take().unwrap();
        assert_eq!(second.len(), 100);
        assert_eq!(names(&second)[0], "500");
        assert_eq!(names(&second)[99], "599");
        assert!(queue.take().is_none());
    }

    #[test]
    fn requeue_restores_the_chronological_order_in_front() {
        let queue = Queue::new(LOG_TABLE);
        queue.submit(row("a"), 0);
        queue.submit(row("b"), 0);
        let batch = queue.take().unwrap();
        queue.submit(row("c"), 0);
        assert_eq!(queue.requeue(batch), 0);
        assert_eq!(names(&queue.take().unwrap()), vec!["a", "b", "c"]);
    }

    #[test]
    fn requeue_past_the_cap_reports_the_overflow() {
        let queue = Queue::new(HTTP);
        let batch: Vec<Vec<u8>> = (0..HTTP.max_pending).map(|_| row("x")).collect();
        assert_eq!(queue.requeue(batch), 0);
        assert_eq!(queue.requeue(vec![row("y"), row("z")]), 2);
        assert_eq!(queue.pending_len(), HTTP.max_pending as u32);
    }

    #[test]
    fn backoff_doubles_from_the_minimum_to_the_cap() {
        let queue = Queue::new(LOG_TABLE);
        assert_eq!(queue.backoff(1_000), 1_000);
        assert_eq!(queue.backoff(2_000), 2_000);
        assert_eq!(queue.backoff(4_000), 4_000);
        assert_eq!(queue.retry_wait_ms(5_000), 3_000);
        assert!(queue.in_backoff(7_999));
        assert!(!queue.in_backoff(8_000));
        for now in [10_000, 20_000, 40_000, 80_000, 160_000] {
            queue.backoff(now);
        }
        assert_eq!(queue.retry_wait_ms(160_000), 30_000);
        queue.reset_backoff();
        assert_eq!(queue.retry_wait_ms(160_000), 0);
        assert!(!queue.in_backoff(160_000));
        // The first failure after a reset starts over at the minimum.
        assert_eq!(queue.backoff(200_000), 1_000);
    }

    #[test]
    fn the_missing_table_latch_expires_and_http_never_latches() {
        let queue = Queue::new(LOG_TABLE);
        assert!(!queue.missing_latched(0));
        queue.latch_missing(1_000);
        assert!(queue.missing_latched(30_999));
        assert!(!queue.missing_latched(31_000));

        let http = Queue::new(HTTP);
        http.latch_missing(1_000);
        assert!(!http.missing_latched(1_001));
    }

    #[test]
    fn a_closed_queue_takes_no_more_rows_and_reports_the_tail() {
        let queue = Queue::new(HTTP);
        queue.submit(row("a"), 0);
        queue.submit(row("b"), 0);
        assert_eq!(queue.close(), 2);
        assert!(queue.is_closed());
        assert_eq!(queue.submit(row("c"), 0), None);
        assert!(queue.take().is_none());
        assert_eq!(queue.close(), 0);
    }
}

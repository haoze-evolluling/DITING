//! The bounded DNS log batch buffer behind `android/engine/log_aggregator.go`.
//!
//! The Go aggregator used to be a buffered channel plus a local batch: the channel length decided
//! throttling, the goroutine that received from it decided batching, and the drop counters lived in
//! `atomic.Uint64` fields next to it. This module owns that queue so the shedding rules and the
//! counters have a single implementation:
//!
//! * a capacity of [`BUFFER_SIZE`] items; a push past it drops (and counts) the item;
//! * above [`HIGH_WATER_MARK`] queued items, non-blocked `"connection"` rows are dropped first so
//!   capacity stays available for DNS rows (both counters advance, exactly like the old Go path);
//! * [`LogAggregator::drain`] hands out up to `max` items in FIFO order.
//!
//! The flush cadence is *not* here: Go keeps the 100 ms lazily armed timer, the callback and the
//! `encoding/json` of a drained batch. Only the buffer, the two decision thresholds and the two
//! counters moved.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};

/// `logBufferSize`: the channel capacity the Go aggregator used to allocate.
pub const BUFFER_SIZE: usize = 2048;
/// `logHighWaterMark`: `(logBufferSize * 3) / 4`.
pub const HIGH_WATER_MARK: usize = (BUFFER_SIZE * 3) / 4;
/// `logBatchSize`: how many rows one flush carries.
pub const BATCH_SIZE: usize = 50;

/// One DNS/connection log row, matching the fields of Go's `logItem`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LogItem {
    pub domain: String,
    pub blocked: bool,
    pub query_type: i32,
    pub response_time_ms: i64,
    pub app_name: String,
    pub resolved_ips: String,
    pub blocked_by: String,
    pub error_message: String,
    pub cached: bool,
    pub timestamp_ms: i64,
    /// Kept even when zero: Kotlin distinguishes "upstream said do not cache" from "TTL unknown".
    pub ttl: i64,
}

/// What a push did, so the caller knows whether a flush is already due.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PushOutcome {
    /// The row was dropped (buffer full, or a connection row above the high-water mark).
    Dropped,
    /// The row is queued and the buffer is still below [`BATCH_SIZE`].
    Buffered,
    /// The row is queued and at least [`BATCH_SIZE`] rows are waiting: flush now.
    Full,
}

struct State {
    items: VecDeque<LogItem>,
}

/// One engine's DNS log buffer.
pub struct LogAggregator {
    state: Mutex<State>,
    dropped: AtomicU64,
    dropped_conn: AtomicU64,
}

impl LogAggregator {
    /// `newLogAggregator`: an empty queue with the counters at zero.
    pub fn new() -> Self {
        Self {
            state: Mutex::new(State {
                items: VecDeque::with_capacity(BUFFER_SIZE),
            }),
            dropped: AtomicU64::new(0),
            dropped_conn: AtomicU64::new(0),
        }
    }

    /// `push`: shed connection rows above the high-water mark, then drop only when the buffer is
    /// full.
    pub fn push(&self, item: LogItem) -> PushOutcome {
        let mut state = self.lock();
        let pending = state.items.len();

        // Tier 1: an unblocked connection row yields its slot to DNS rows once the queue is
        // three-quarters full. Both counters advance, exactly like the Go aggregator.
        if !item.blocked && item.blocked_by == "connection" && pending >= HIGH_WATER_MARK {
            self.dropped_conn.fetch_add(1, Ordering::Relaxed);
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return PushOutcome::Dropped;
        }

        // Tier 2: full. The item is dropped silently (counted) so nothing blocks the packet path.
        if pending >= BUFFER_SIZE {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return PushOutcome::Dropped;
        }

        state.items.push_back(item);
        if state.items.len() >= BATCH_SIZE {
            PushOutcome::Full
        } else {
            PushOutcome::Buffered
        }
    }

    /// Hands out the oldest `max` rows and reports how many are still queued.
    pub fn drain(&self, max: usize) -> (Vec<LogItem>, usize) {
        let mut state = self.lock();
        let take = max.min(state.items.len());
        let items: Vec<LogItem> = state.items.drain(..take).collect();
        (items, state.items.len())
    }

    /// Rows waiting for a flush.
    pub fn pending(&self) -> usize {
        self.lock().items.len()
    }

    /// `droppedLogs`: every dropped row (shed connection rows included).
    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    /// `droppedConnLogs`: only the connection rows shed above the high-water mark.
    pub fn dropped_conn(&self) -> u64 {
        self.dropped_conn.load(Ordering::Relaxed)
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

impl Default for LogAggregator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests;

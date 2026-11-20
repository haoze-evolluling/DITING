use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};

pub const BUFFER_SIZE: usize = 2048;
pub const HIGH_WATER_MARK: usize = (BUFFER_SIZE * 3) / 4;
pub const BATCH_SIZE: usize = 50;

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
    pub ttl: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PushOutcome {
    Dropped,
    Buffered,
    Full,
}

struct State {
    items: VecDeque<LogItem>,
}

pub struct LogAggregator {
    state: Mutex<State>,
    dropped: AtomicU64,
    dropped_conn: AtomicU64,
}

impl LogAggregator {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(State {
                items: VecDeque::with_capacity(BUFFER_SIZE),
            }),
            dropped: AtomicU64::new(0),
            dropped_conn: AtomicU64::new(0),
        }
    }

    pub fn push(&self, item: LogItem) -> PushOutcome {
        let mut state = self.lock();
        let pending = state.items.len();

        if !item.blocked && item.blocked_by == "connection" && pending >= HIGH_WATER_MARK {
            self.dropped_conn.fetch_add(1, Ordering::Relaxed);
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return PushOutcome::Dropped;
        }

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

    pub fn drain(&self, max: usize) -> (Vec<LogItem>, usize) {
        let mut state = self.lock();
        let take = max.min(state.items.len());
        let items: Vec<LogItem> = state.items.drain(..take).collect();
        (items, state.items.len())
    }

    pub fn pending(&self) -> usize {
        self.lock().items.len()
    }

    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

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

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

pub const DEFAULT_TICK_INTERVAL_MS: i64 = 1000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Delta {
    pub uid: i32,
    pub tx: u64,
    pub rx: u64,
}

struct Counters {
    tx_delta: AtomicU64,
    rx_delta: AtomicU64,
    tx_total: AtomicU64,
    rx_total: AtomicU64,
}

impl Counters {
    fn new() -> Self {
        Self {
            tx_delta: AtomicU64::new(0),
            rx_delta: AtomicU64::new(0),
            tx_total: AtomicU64::new(0),
            rx_total: AtomicU64::new(0),
        }
    }

    fn add(&self, tx: i64, rx: i64) {
        if tx > 0 {
            let bytes = tx as u64;
            self.tx_delta.fetch_add(bytes, Ordering::Relaxed);
            self.tx_total.fetch_add(bytes, Ordering::Relaxed);
        }
        if rx > 0 {
            let bytes = rx as u64;
            self.rx_delta.fetch_add(bytes, Ordering::Relaxed);
            self.rx_total.fetch_add(bytes, Ordering::Relaxed);
        }
    }
}

struct State {
    uids: HashMap<i32, Counters>,
    interval_ms: i64,
}

pub struct TrafficTracker {
    state: RwLock<State>,
}

impl TrafficTracker {
    pub fn new() -> Self {
        Self {
            state: RwLock::new(State {
                uids: HashMap::new(),
                interval_ms: DEFAULT_TICK_INTERVAL_MS,
            }),
        }
    }

    pub fn record(&self, uid: i32, tx: i64, rx: i64) {
        if uid <= 0 || (tx <= 0 && rx <= 0) {
            return;
        }
        {
            let state = self.read();
            if let Some(counters) = state.uids.get(&uid) {
                counters.add(tx, rx);
                return;
            }
        }
        let mut state = self.write();
        state
            .uids
            .entry(uid)
            .or_insert_with(Counters::new)
            .add(tx, rx);
    }

    pub fn tick(&self) -> Vec<Delta> {
        let state = self.read();
        if state.uids.is_empty() {
            return Vec::new();
        }
        let mut deltas = Vec::new();
        for (uid, counters) in state.uids.iter() {
            let tx = counters.tx_delta.swap(0, Ordering::Relaxed);
            let rx = counters.rx_delta.swap(0, Ordering::Relaxed);
            if tx > 0 || rx > 0 {
                deltas.push(Delta { uid: *uid, tx, rx });
            }
        }
        deltas
    }

    pub fn set_interval_ms(&self, interval_ms: i64) {
        if interval_ms <= 0 {
            return;
        }
        self.write().interval_ms = interval_ms;
    }

    pub fn interval_ms(&self) -> i64 {
        self.read().interval_ms
    }

    pub fn unique_uids(&self) -> u32 {
        self.read().uids.len() as u32
    }

    pub fn totals(&self, uid: i32) -> Option<(u64, u64)> {
        self.read().uids.get(&uid).map(|counters| {
            (
                counters.tx_total.load(Ordering::Relaxed),
                counters.rx_total.load(Ordering::Relaxed),
            )
        })
    }

    fn read(&self) -> RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl Default for TrafficTracker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests;

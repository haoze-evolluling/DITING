//! The per-UID byte accounting behind `android/engine/traffic_tracker.go`.
//!
//! Go used to keep `map[int]*uidTrafficCounters` behind an `RWMutex` and cached the counter pointer
//! on every wrapped connection so a `Read`/`Write` was two atomic adds. This module owns the map and
//! the four atomics per UID (`tx/rx` delta and total); `record` performs the same "ignore an
//! unattributable UID or a non-positive count" gate and `tick` swaps the deltas out exactly like
//! `tick()` did, leaving the totals in place.
//!
//! The reporting cadence stays in Go: the ticker goroutine, the wake-up channel, the
//! `TrafficCallback` and the `encoding/json` of one tick. So does the `net.Conn` wrapper that turns
//! each `Read`/`Write` into one `record` call. The kernel never reads a clock, so a scripted tick
//! sequence is deterministic and testable.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

/// `defaultTickInterval`: the reporting interval used until Kotlin pushes the screen state.
pub const DEFAULT_TICK_INTERVAL_MS: i64 = 1000;

/// One UID's deltas since the last tick, newest first is irrelevant (Kotlin sums them).
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

    /// `RecordTx` + `RecordRx` for one call: each side is added only when positive, so a `Read`
    /// (tx) and a `Write` (rx) cannot drift from the Go version's two separate entry points.
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

/// One engine's traffic accounting state.
pub struct TrafficTracker {
    state: RwLock<State>,
}

impl TrafficTracker {
    /// `newTrafficTracker`: no UIDs yet, one-second cadence.
    pub fn new() -> Self {
        Self {
            state: RwLock::new(State {
                uids: HashMap::new(),
                interval_ms: DEFAULT_TICK_INTERVAL_MS,
            }),
        }
    }

    /// `RecordTx` / `RecordRx`: an unattributable UID (`<= 0`) or a non-positive count is ignored;
    /// the counters are created on first use and never removed.
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
        // A concurrent `record` may have inserted the entry between the two locks; `entry` keeps
        // the first counter block, so both callers add to the same atomics.
        state
            .uids
            .entry(uid)
            .or_insert_with(Counters::new)
            .add(tx, rx);
    }

    /// `tick`: swap every UID's deltas to zero and return the rows that saw traffic.
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

    /// `SetTickInterval`: a non-positive duration keeps the current cadence.
    pub fn set_interval_ms(&self, interval_ms: i64) {
        if interval_ms <= 0 {
            return;
        }
        self.write().interval_ms = interval_ms;
    }

    /// The cadence the Go ticker arms its timer with.
    pub fn interval_ms(&self) -> i64 {
        self.read().interval_ms
    }

    /// How many UIDs have counters (the `len(t.uids) == 0` early return).
    pub fn unique_uids(&self) -> u32 {
        self.read().uids.len() as u32
    }

    /// `(txTotal, rxTotal)` for one UID; `None` when it has never been recorded.
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

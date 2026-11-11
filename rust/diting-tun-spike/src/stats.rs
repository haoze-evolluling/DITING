//! The counters and the one JSON document the Kotlin side reads.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use serde_json::json;

use crate::callback::CallbackStats;
use crate::protector::Evidence;

/// Data-plane counters, all monotonic (the Kotlin side plots the deltas).
#[derive(Debug, Default)]
pub struct Counters {
    /// Packets read from the TUN source.
    pub read: AtomicU64,
    /// Bytes read from the TUN source.
    pub bytes_in: AtomicU64,
    /// Packets dropped because the worker queue was full.
    pub dropped: AtomicU64,
    /// Callbacks handed to the dispatcher (a full callback queue is counted there).
    pub events: AtomicU64,
    /// Writes to the protected upstream socket that failed.
    pub write_failures: AtomicU64,
    /// Reads that returned `EAGAIN`/`EINTR` and were retried immediately.
    pub retries: AtomicU64,
    /// Reads that returned `ENETDOWN`/`EBUSY`/`ENOBUFS` and backed off.
    pub backoffs: AtomicU64,
}

impl Counters {
    pub fn get(&self, counter: &AtomicU64) -> u64 {
        counter.load(Ordering::SeqCst)
    }
}

/// `getStats()`: the document the Kotlin facade parses (field names must stay stable).
pub fn stats_json(
    live: usize,
    counters: &Counters,
    evidence: &Evidence,
    callbacks: &CallbackStats,
    connected: bool,
    error: Option<&str>,
) -> String {
    json!({
        "live": live,
        "connected": connected,
        "error": error,
        "pipeline": {
            "read": counters.get(&counters.read),
            "bytes": counters.get(&counters.bytes_in),
            "dropped": counters.get(&counters.dropped),
            "events": counters.get(&counters.events),
            "writeFailures": counters.get(&counters.write_failures),
            "retries": counters.get(&counters.retries),
            "backoffs": counters.get(&counters.backoffs),
        },
        "callbacks": {
            "delivered": callbacks.delivered,
            "dropped": callbacks.dropped,
            "panics": callbacks.panics,
            "thread": callbacks.thread,
        },
        "protect": {
            "calls": evidence.protect_calls.load(Ordering::SeqCst),
            "denied": evidence.denied.load(Ordering::SeqCst),
            "connects": evidence.connects.load(Ordering::SeqCst),
            "connectFailures": evidence.connect_failures.load(Ordering::SeqCst),
            "beforeConnect": evidence.protect_before_connect.load(Ordering::SeqCst),
        },
    })
    .to_string()
}

/// Tracked once per session so `getStats` can say whether a dial is up.
#[derive(Debug, Default)]
pub struct ConnectionState {
    connected: AtomicBool,
}

impl ConnectionState {
    pub fn set(&self, connected: bool) {
        self.connected.store(connected, Ordering::SeqCst);
    }

    pub fn get(&self) -> bool {
        self.connected.load(Ordering::SeqCst)
    }
}

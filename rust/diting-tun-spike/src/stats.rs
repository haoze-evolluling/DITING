use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use serde_json::json;

use crate::callback::CallbackStats;
use crate::protector::Evidence;

#[derive(Debug, Default)]
pub struct Counters {
    pub read: AtomicU64,
    pub bytes_in: AtomicU64,
    pub dropped: AtomicU64,
    pub events: AtomicU64,
    pub write_failures: AtomicU64,
    pub retries: AtomicU64,
    pub backoffs: AtomicU64,
}

impl Counters {
    pub fn get(&self, counter: &AtomicU64) -> u64 {
        counter.load(Ordering::SeqCst)
    }
}

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

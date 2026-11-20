use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

use crate::tuning::TUNING;

struct Entry {
    id: u64,
    last_used_ms: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Acquired {
    Idle(u64),
    Expired(u64),
}

pub struct DotPool {
    state: Mutex<HashMap<String, Vec<Entry>>>,
}

impl DotPool {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(HashMap::new()),
        }
    }

    pub fn acquire(&self, host: &str, now_ms: i64) -> Option<Acquired> {
        let mut state = self.lock();
        let (entry, empty) = {
            let entries = state.get_mut(host)?;
            let entry = entries.pop()?;
            (entry, entries.is_empty())
        };
        if empty {
            state.remove(host);
        }
        if now_ms.saturating_sub(entry.last_used_ms) > TUNING.dot_idle_timeout_ms {
            Some(Acquired::Expired(entry.id))
        } else {
            Some(Acquired::Idle(entry.id))
        }
    }

    pub fn release(&self, host: &str, id: u64, now_ms: i64) -> bool {
        let mut state = self.lock();
        let entries = state.entry(host.to_string()).or_default();
        if entries.len() < TUNING.dot_max_idle_conns_per_host as usize {
            entries.push(Entry {
                id,
                last_used_ms: now_ms,
            });
            true
        } else {
            false
        }
    }

    pub fn close_all(&self) -> Vec<u64> {
        let mut state = self.lock();
        let mut ids = Vec::new();
        for (_, entries) in state.drain() {
            ids.extend(entries.into_iter().map(|entry| entry.id));
        }
        ids
    }

    pub fn len(&self, host: &str) -> u32 {
        self.lock()
            .get(host)
            .map_or(0, |entries| entries.len() as u32)
    }

    pub fn is_empty(&self) -> bool {
        self.lock().is_empty()
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<String, Vec<Entry>>> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

impl Default for DotPool {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests;

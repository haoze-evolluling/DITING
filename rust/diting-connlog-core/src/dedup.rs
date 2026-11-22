use std::collections::HashSet;
use std::sync::{Mutex, MutexGuard};

use crate::key::build_key;

pub const MAX_ENTRIES: usize = 8192;

struct State {
    seen: HashSet<String>,
    cleared: u64,
}

impl Default for State {
    fn default() -> Self {
        Self {
            seen: HashSet::with_capacity(MAX_ENTRIES),
            cleared: 0,
        }
    }
}

#[derive(Default)]
pub struct ConnLogDedup {
    state: Mutex<State>,
}

impl ConnLogDedup {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn mark(
        &self,
        prefix: &str,
        app: &str,
        dest: &str,
        port: i32,
        protocol: i32,
        reason: &str,
    ) -> bool {
        self.mark_key(build_key(prefix, app, dest, port, protocol, reason))
    }

    pub fn mark_key(&self, key: String) -> bool {
        let mut state = self.lock();
        if state.seen.contains(&key) {
            return true;
        }
        if state.seen.len() >= MAX_ENTRIES {
            state.seen = HashSet::with_capacity(MAX_ENTRIES);
            state.cleared += 1;
        }
        state.seen.insert(key);
        false
    }

    pub fn reset(&self) {
        let mut state = self.lock();
        state.seen = HashSet::with_capacity(MAX_ENTRIES);
    }

    pub fn size(&self) -> u32 {
        self.lock().seen.len() as u32
    }

    pub fn cleared(&self) -> u64 {
        self.lock().cleared
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests;

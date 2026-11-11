//! The DoT idle connection pool.
//!
//! `resolver_dot.go` kept `map[string][]*dotConnEntry` behind `dotMu`: the tail was the newest
//! connection, `popIdleDoTConn` popped from the tail (LIFO), discarded entries older than 15 s, and
//! `putIdleDoTConn` appended while the per-host list stayed below 4. Here the *policy* owns the
//! list; the `*tls.Conn` values stay in Go under their numeric ids, because a socket is not
//! something a kernel can hold.
//!
//! The caller probes liveness (`isAlive`) and closes the sockets; the kernel only answers "which id
//! is the next candidate", "this one is past its idle window" and "keep it or close it".

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

use crate::tuning::TUNING;

struct Entry {
    id: u64,
    last_used_ms: i64,
}

/// What [`DotPool::acquire`] found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Acquired {
    /// The newest entry still inside the idle window: probe it and reuse it if it is alive.
    Idle(u64),
    /// Older than [`TUNING::dot_idle_timeout_ms`]: the caller closes it and asks again.
    Expired(u64),
}

/// One resolver's idle DoT connections, one list per dial target.
pub struct DotPool {
    state: Mutex<HashMap<String, Vec<Entry>>>,
}

impl DotPool {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(HashMap::new()),
        }
    }

    /// `popIdleDoTConn`'s policy half: pop the newest entry and classify it. `None` means the list
    /// for this target is empty (dial a fresh connection).
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
        // `time.Since(lastUsed) <= dotIdleTimeout` keeps the entry; anything older is expired.
        if now_ms.saturating_sub(entry.last_used_ms) > TUNING.dot_idle_timeout_ms {
            Some(Acquired::Expired(entry.id))
        } else {
            Some(Acquired::Idle(entry.id))
        }
    }

    /// `putIdleDoTConn`: keep the connection when the host still has room, otherwise report that the
    /// caller has to close it.
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

    /// Every id currently pooled, so the caller can close those sockets. The pool is emptied.
    pub fn close_all(&self) -> Vec<u64> {
        let mut state = self.lock();
        let mut ids = Vec::new();
        for (_, entries) in state.drain() {
            ids.extend(entries.into_iter().map(|entry| entry.id));
        }
        ids
    }

    /// Idle entries for one target (test/telemetry helper).
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

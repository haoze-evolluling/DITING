use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

pub const RESPONSE_CUSTOM_IP: u32 = 0;
pub const RESPONSE_NX_DOMAIN: u32 = 1;
pub const RESPONSE_REFUSED: u32 = 2;
pub const RESPONSE_NO_DATA: u32 = 3;

pub const MAX_ENTRIES: usize = 4096;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BlockConfig {
    pub enabled: bool,
    pub request_threshold: u32,
    pub window_ns: i64,
    pub nx_domain_ns: i64,
}

#[derive(Debug, Clone, Copy)]
struct Entry {
    window_started_ns: i64,
    request_count: u32,
    nx_domain_until_ns: i64,
}

pub struct DynamicBlocks {
    entries: Mutex<HashMap<String, Entry>>,
}

impl Default for DynamicBlocks {
    fn default() -> Self {
        Self::new()
    }
}

impl DynamicBlocks {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    pub fn reset(&self) {
        self.lock().clear();
    }

    pub fn response_for(
        &self,
        domain: &str,
        config: &BlockConfig,
        fallback: u32,
        now_ns: i64,
    ) -> u32 {
        if !config.enabled {
            return fallback;
        }

        let mut entries = self.lock();
        if let Some(entry) = entries.get(domain) {
            if now_ns < entry.nx_domain_until_ns {
                return RESPONSE_NX_DOMAIN;
            }
        }

        let mut entry = match entries.get(domain) {
            Some(existing)
                if now_ns.saturating_sub(existing.window_started_ns) < config.window_ns =>
            {
                Entry {
                    window_started_ns: existing.window_started_ns,
                    request_count: existing.request_count.saturating_add(1),
                    nx_domain_until_ns: existing.nx_domain_until_ns,
                }
            }
            _ => Entry {
                window_started_ns: now_ns,
                request_count: 1,
                nx_domain_until_ns: 0,
            },
        };

        let escalated = entry.request_count > config.request_threshold;
        if escalated {
            entry.nx_domain_until_ns = now_ns.saturating_add(config.nx_domain_ns);
        }
        entries.insert(domain.to_string(), entry);

        if escalated {
            return RESPONSE_NX_DOMAIN;
        }
        if entries.len() > MAX_ENTRIES {
            if let Some(key) = entries.keys().next().cloned() {
                entries.remove(&key);
            }
        }
        RESPONSE_NO_DATA
    }

    pub fn len(&self) -> usize {
        self.lock().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<String, Entry>> {
        self.entries
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[cfg(test)]
mod tests;

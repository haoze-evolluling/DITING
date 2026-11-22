use std::collections::HashMap;
use std::sync::Mutex;

use diting_dns_wire::question_key;

pub const NEGATIVE_TTL_NS: i64 = 3_000_000_000;
pub const MAX_ENTRIES: usize = 4096;

struct Entry {
    expires_ns: i64,
    error: String,
}

/// 上游与系统 DNS 都失败后的短暂负缓存。应用在故障期会成倍重试，
/// 缓存几秒可以避免每次重试都把六台上游重新打满。
#[derive(Default)]
pub struct NegativeCache {
    entries: Mutex<HashMap<Vec<u8>, Entry>>,
}

impl NegativeCache {
    pub fn get(&self, query: &[u8], now_ns: i64) -> Option<String> {
        let key = question_key(query)?.key;
        let mut entries = self.lock();
        match entries.get(&key) {
            Some(entry) if entry.expires_ns > now_ns => Some(entry.error.clone()),
            Some(_) => {
                entries.remove(&key);
                None
            }
            None => None,
        }
    }

    pub fn put(&self, query: &[u8], error: &str, now_ns: i64) {
        let Some(key) = question_key(query).map(|key| key.key) else {
            return;
        };
        let mut entries = self.lock();
        entries.retain(|_, entry| entry.expires_ns > now_ns);
        if entries.len() >= MAX_ENTRIES {
            entries.clear();
        }
        entries.insert(
            key,
            Entry {
                expires_ns: now_ns.saturating_add(NEGATIVE_TTL_NS),
                error: error.to_string(),
            },
        );
    }

    pub fn remove(&self, query: &[u8]) {
        if let Some(key) = question_key(query).map(|key| key.key) {
            self.lock().remove(&key);
        }
    }

    pub fn clear(&self) {
        self.lock().clear();
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<Vec<u8>, Entry>> {
        self.entries
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::resolver::build_query;

    #[test]
    fn an_error_is_served_until_the_ttl_expires() {
        let cache = NegativeCache::default();
        let query = build_query("example.com.", 1);
        assert!(cache.get(&query, 10).is_none());
        cache.put(&query, "timed out", 10);
        assert_eq!(cache.get(&query, 20).as_deref(), Some("timed out"));
        assert!(cache.get(&query, NEGATIVE_TTL_NS + 11).is_none());
    }

    #[test]
    fn different_query_ids_share_one_entry() {
        let cache = NegativeCache::default();
        let first = build_query("example.com.", 1);
        let mut second = first.clone();
        second[0] ^= 0xff;
        second[1] ^= 0xff;
        cache.put(&first, "boom", 0);
        assert_eq!(cache.get(&second, 1).as_deref(), Some("boom"));
        cache.remove(&second);
        assert!(cache.get(&first, 2).is_none());
    }
}

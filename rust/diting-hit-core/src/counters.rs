use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Mutex;

pub const SHARDS: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HitEntry {
    pub rule_id: i64,
    pub list_id: Option<i64>,
    pub count: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct Key {
    rule_id: i64,
    list_id: Option<i64>,
}

pub struct HitCounters {
    shards: Vec<Mutex<HashMap<Key, u64>>>,
    mask: usize,
}

impl HitCounters {
    pub fn new() -> Self {
        Self::with_shards(SHARDS)
    }

    pub fn with_shards(shards: usize) -> Self {
        let shards = shards.max(1).next_power_of_two();
        let mut shard_maps = Vec::with_capacity(shards);
        for _ in 0..shards {
            shard_maps.push(Mutex::new(HashMap::new()));
        }
        HitCounters {
            shards: shard_maps,
            mask: shards - 1,
        }
    }

    fn shard(&self, key: &Key) -> &Mutex<HashMap<Key, u64>> {
        let mut hasher = DefaultHasher::new();
        key.hash(&mut hasher);
        let index = (hasher.finish() as usize) & self.mask;
        &self.shards[index]
    }

    pub fn increment(&self, rule_id: i64, list_id: Option<i64>) {
        self.increment_by(rule_id, list_id, 1);
    }

    pub fn increment_by(&self, rule_id: i64, list_id: Option<i64>, amount: u64) {
        if amount == 0 {
            return;
        }
        let key = Key { rule_id, list_id };
        let mut shard = self
            .shard(&key)
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        *shard.entry(key).or_insert(0) += amount;
    }

    pub fn snapshot(&self) -> Vec<HitEntry> {
        let mut rows = Vec::new();
        for shard in &self.shards {
            let guard = shard
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            for (key, count) in guard.iter() {
                if *count > 0 {
                    rows.push(HitEntry {
                        rule_id: key.rule_id,
                        list_id: key.list_id,
                        count: *count,
                    });
                }
            }
        }
        rows.sort_by_key(|row| (row.rule_id, row.list_id));
        rows
    }

    pub fn total(&self) -> u64 {
        self.shards
            .iter()
            .map(|shard| {
                shard
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .values()
                    .sum::<u64>()
            })
            .sum()
    }

    pub fn reset(&self) {
        for shard in &self.shards {
            shard
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .clear();
        }
    }
}

impl Default for HitCounters {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn collects_and_sorts_rows() {
        let counters = HitCounters::new();
        counters.increment(5, None);
        counters.increment(5, Some(2));
        counters.increment(1, Some(9));
        counters.increment_by(1, Some(9), 3);
        let snapshot = counters.snapshot();
        assert_eq!(
            snapshot,
            vec![
                HitEntry {
                    rule_id: 1,
                    list_id: Some(9),
                    count: 4
                },
                HitEntry {
                    rule_id: 5,
                    list_id: None,
                    count: 1
                },
                HitEntry {
                    rule_id: 5,
                    list_id: Some(2),
                    count: 1
                },
            ]
        );
        assert_eq!(counters.total(), 6);
    }

    #[test]
    fn list_and_global_keys_are_distinct() {
        let counters = HitCounters::with_shards(1);
        counters.increment(7, None);
        counters.increment(7, Some(0));
        assert_eq!(counters.snapshot().len(), 2);
    }

    #[test]
    fn concurrent_increments_do_not_lose_a_count() {
        let counters = Arc::new(HitCounters::new());
        let mut handles = Vec::new();
        for _ in 0..8 {
            let counters = Arc::clone(&counters);
            handles.push(std::thread::spawn(move || {
                for _ in 0..1_000 {
                    counters.increment(42, Some(1));
                }
            }));
        }
        for handle in handles {
            handle.join().expect("thread");
        }
        assert_eq!(counters.total(), 8_000);
        let snapshot = counters.snapshot();
        assert_eq!(snapshot.len(), 1);
        assert_eq!(snapshot[0].count, 8_000);
    }

    #[test]
    fn reset_clears_every_shard() {
        let counters = HitCounters::new();
        counters.increment(1, None);
        counters.increment(2, Some(3));
        counters.reset();
        assert!(counters.snapshot().is_empty());
        assert_eq!(counters.total(), 0);
    }
}

use std::collections::{BTreeMap, HashMap};
use std::sync::Mutex;

pub const FLOW_CACHE_CAPACITY: usize = 1024;
pub const PACKAGE_CACHE_CAPACITY: usize = 256;
pub const FLOW_CACHE_TTL_MS: i64 = 10_000;
pub const FLOW_NEGATIVE_CACHE_TTL_MS: i64 = 2_000;
pub const INVALID_UID: i32 = -1;

pub fn is_known_uid(uid: i32) -> bool {
    uid > 0 && uid != INVALID_UID
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct FlowKey {
    pub protocol: i64,
    pub local_ip: String,
    pub local_port: i64,
    pub remote_ip: String,
    pub remote_port: i64,
}

#[derive(Debug, Clone, Copy)]
struct CachedUid {
    uid: i32,
    timestamp: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PackageLookup {
    Hit(String),
    Miss,
    NotKnown,
}

#[derive(Debug)]
struct Lru<K, V> {
    capacity: usize,
    entries: HashMap<K, (V, u64)>,
    order: BTreeMap<u64, K>,
    clock: u64,
}

impl<K: std::hash::Hash + Eq + Clone, V> Lru<K, V> {
    fn new(capacity: usize) -> Self {
        Self {
            capacity,
            entries: HashMap::new(),
            order: BTreeMap::new(),
            clock: 0,
        }
    }

    fn get(&mut self, key: &K) -> Option<&V> {
        let previous = self.entries.get(key).map(|(_, stamp)| *stamp)?;
        self.clock = self.clock.wrapping_add(1);
        let stamp = self.clock;
        self.order.remove(&previous);
        self.order.insert(stamp, key.clone());
        let entry = self.entries.get_mut(key)?;
        entry.1 = stamp;
        Some(&entry.0)
    }

    fn put(&mut self, key: K, value: V) {
        self.clock = self.clock.wrapping_add(1);
        let stamp = self.clock;
        if let Some((_, previous)) = self.entries.insert(key.clone(), (value, stamp)) {
            self.order.remove(&previous);
        }
        self.order.insert(stamp, key);
        while self.entries.len() > self.capacity {
            let Some(oldest) = self.order.keys().next().copied() else {
                break;
            };
            if let Some(evicted) = self.order.remove(&oldest) {
                self.entries.remove(&evicted);
            }
        }
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.order.clear();
    }

    fn len(&self) -> usize {
        self.entries.len()
    }
}

pub struct Attr {
    flows: Mutex<Lru<FlowKey, CachedUid>>,
    packages: Mutex<Lru<i32, String>>,
}

impl Default for Attr {
    fn default() -> Self {
        Self::new()
    }
}

impl Attr {
    pub fn new() -> Self {
        Self {
            flows: Mutex::new(Lru::new(FLOW_CACHE_CAPACITY)),
            packages: Mutex::new(Lru::new(PACKAGE_CACHE_CAPACITY)),
        }
    }

    pub fn lookup_uid(&self, key: &FlowKey, now_ms: i64) -> Option<i32> {
        let mut flows = self.flows.lock().unwrap_or_else(|error| error.into_inner());
        let cached = flows.get(key).copied()?;
        let ttl = if is_known_uid(cached.uid) {
            FLOW_CACHE_TTL_MS
        } else {
            FLOW_NEGATIVE_CACHE_TTL_MS
        };
        if now_ms.wrapping_sub(cached.timestamp) < ttl {
            Some(cached.uid)
        } else {
            None
        }
    }

    pub fn store_uid(&self, key: FlowKey, uid: i32, now_ms: i64) {
        let mut flows = self.flows.lock().unwrap_or_else(|error| error.into_inner());
        flows.put(
            key,
            CachedUid {
                uid,
                timestamp: now_ms,
            },
        );
    }

    pub fn lookup_package(&self, uid: i32) -> PackageLookup {
        if !is_known_uid(uid) {
            return PackageLookup::NotKnown;
        }
        let mut packages = self
            .packages
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        match packages.get(&uid) {
            Some(name) => PackageLookup::Hit(name.clone()),
            None => PackageLookup::Miss,
        }
    }

    pub fn store_package(&self, uid: i32, name: &str) {
        if name.is_empty() {
            return;
        }
        let mut packages = self
            .packages
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        packages.put(uid, name.to_string());
    }

    pub fn clear(&self) {
        self.flows
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clear();
        self.packages
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clear();
    }

    pub fn flow_len(&self) -> u32 {
        self.flows
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .len() as u32
    }

    pub fn package_len(&self) -> u32 {
        self.packages
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .len() as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(local_port: i64) -> FlowKey {
        FlowKey {
            protocol: 6,
            local_ip: "10.0.0.2".into(),
            local_port,
            remote_ip: "1.2.3.4".into(),
            remote_port: 443,
        }
    }

    #[test]
    fn known_uids_live_ten_seconds_and_unknown_ones_two() {
        let attr = Attr::new();
        attr.store_uid(key(1), 10001, 1_000);
        assert_eq!(attr.lookup_uid(&key(1), 10_999), Some(10001));
        assert_eq!(attr.lookup_uid(&key(1), 11_000), None);

        attr.store_uid(key(2), INVALID_UID, 1_000);
        assert_eq!(attr.lookup_uid(&key(2), 2_999), Some(INVALID_UID));
        assert_eq!(attr.lookup_uid(&key(2), 3_000), None);

        attr.store_uid(key(3), 0, 1_000);
        assert_eq!(attr.lookup_uid(&key(3), 2_500), Some(0));
        assert_eq!(attr.lookup_uid(&key(3), 3_001), None);
    }

    #[test]
    fn an_expired_flow_entry_is_still_promoted() {
        let attr = Attr::new();
        for port in 1..=(FLOW_CACHE_CAPACITY as i64) {
            attr.store_uid(key(port), 10001, 0);
        }
        assert_eq!(attr.lookup_uid(&key(1), 20_000), None);
        attr.store_uid(key(0), 10001, 20_000);
        assert_eq!(attr.flow_len(), FLOW_CACHE_CAPACITY as u32);
        assert_eq!(attr.lookup_uid(&key(2), 20_000), None);
        assert_eq!(attr.flow_len(), FLOW_CACHE_CAPACITY as u32);
    }

    #[test]
    fn the_flow_cache_evicts_the_least_recently_used_entry() {
        let attr = Attr::new();
        for port in 1..=(FLOW_CACHE_CAPACITY as i64) {
            attr.store_uid(key(port), 10001, 0);
        }
        assert_eq!(attr.lookup_uid(&key(1), 1), Some(10001));
        attr.store_uid(key(0), 10001, 1);
        assert_eq!(attr.flow_len(), FLOW_CACHE_CAPACITY as u32);
        assert_eq!(attr.lookup_uid(&key(2), 2), None);
        assert_eq!(attr.lookup_uid(&key(1), 2), Some(10001));
    }

    #[test]
    fn packages_are_cached_without_a_ttl() {
        let attr = Attr::new();
        assert_eq!(attr.lookup_package(10001), PackageLookup::Miss);
        attr.store_package(10001, "com.example");
        assert_eq!(
            attr.lookup_package(10001),
            PackageLookup::Hit("com.example".into())
        );
        attr.store_package(10002, "");
        assert_eq!(attr.lookup_package(10002), PackageLookup::Miss);
        assert_eq!(attr.lookup_package(0), PackageLookup::NotKnown);
        assert_eq!(attr.lookup_package(INVALID_UID), PackageLookup::NotKnown);
        assert_eq!(attr.package_len(), 1);
    }

    #[test]
    fn the_package_cache_evicts_past_its_capacity() {
        let attr = Attr::new();
        for uid in 1..=(PACKAGE_CACHE_CAPACITY as i32) {
            attr.store_package(uid + 10_000, "com.example");
        }
        attr.store_package(60_000, "com.last");
        assert_eq!(attr.package_len(), PACKAGE_CACHE_CAPACITY as u32);
        assert_eq!(attr.lookup_package(10_001), PackageLookup::Miss);
        assert_eq!(
            attr.lookup_package(60_000),
            PackageLookup::Hit("com.last".into())
        );
        attr.clear();
        assert_eq!(attr.package_len(), 0);
        assert_eq!(attr.flow_len(), 0);
    }
}

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

pub const FLOW_UID_CACHE_TTL_NS: i64 = 2_000_000_000;
pub const FLOW_UID_NEGATIVE_CACHE_TTL_NS: i64 = 500_000_000;
pub const FLOW_UID_CACHE_MAX_ENTRIES: usize = 1024;
pub const UID_PACKAGE_CACHE_TTL_NS: i64 = 60_000_000_000;
pub const UID_PACKAGE_CACHE_MAX_ENTRIES: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Addr {
    V4([u8; 4]),
    V6([u8; 16]),
}

impl Addr {
    pub fn from_bytes(bytes: &[u8]) -> Option<Addr> {
        match bytes.len() {
            4 => Some(Addr::V4(bytes.try_into().ok()?)),
            16 => Some(Addr::V6(bytes.try_into().ok()?)),
            _ => None,
        }
    }

    pub fn as_bytes(&self) -> &[u8] {
        match self {
            Addr::V4(bytes) => bytes,
            Addr::V6(bytes) => bytes,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FlowKey {
    pub app: Addr,
    pub server: Addr,
    pub app_port: u16,
    pub server_port: u16,
    pub protocol: u8,
}

impl FlowKey {
    pub fn new(app: Addr, app_port: i32, server: Addr, server_port: i32, protocol: i32) -> Self {
        Self {
            app,
            server,
            app_port: app_port as u16,
            server_port: server_port as u16,
            protocol: protocol as u8,
        }
    }
}

struct FlowEntry {
    uid: i32,
    expires_ns: i64,
}

pub struct FlowUidCache {
    entries: Mutex<HashMap<FlowKey, FlowEntry>>,
}

impl FlowUidCache {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    pub fn lookup(&self, key: &FlowKey, now_ns: i64) -> Option<i32> {
        let entries = self.lock();
        entries
            .get(key)
            .filter(|entry| now_ns < entry.expires_ns)
            .map(|entry| entry.uid)
    }

    pub fn store(&self, key: FlowKey, uid: i32, now_ns: i64) {
        let ttl = if uid <= 0 {
            FLOW_UID_NEGATIVE_CACHE_TTL_NS
        } else {
            FLOW_UID_CACHE_TTL_NS
        };
        let mut entries = self.lock();
        if entries.len() >= FLOW_UID_CACHE_MAX_ENTRIES {
            entries.retain(|_, entry| now_ns < entry.expires_ns);
            if entries.len() >= FLOW_UID_CACHE_MAX_ENTRIES {
                entries.clear();
            }
        }
        entries.insert(
            key,
            FlowEntry {
                uid,
                expires_ns: now_ns.saturating_add(ttl),
            },
        );
    }

    pub fn len(&self) -> u32 {
        self.lock().len() as u32
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<FlowKey, FlowEntry>> {
        self.entries
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl Default for FlowUidCache {
    fn default() -> Self {
        Self::new()
    }
}

struct PackageEntry {
    name: String,
    expires_ns: i64,
}

pub struct UidPackageCache {
    entries: Mutex<HashMap<i32, PackageEntry>>,
}

impl UidPackageCache {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    pub fn lookup(&self, uid: i32, now_ns: i64) -> Option<String> {
        let entries = self.lock();
        entries
            .get(&uid)
            .filter(|entry| now_ns < entry.expires_ns)
            .map(|entry| entry.name.clone())
    }

    pub fn store(&self, uid: i32, name: &str, now_ns: i64) {
        if name.is_empty() {
            return;
        }
        let mut entries = self.lock();
        if entries.len() >= UID_PACKAGE_CACHE_MAX_ENTRIES {
            entries.clear();
        }
        entries.insert(
            uid,
            PackageEntry {
                name: name.to_string(),
                expires_ns: now_ns.saturating_add(UID_PACKAGE_CACHE_TTL_NS),
            },
        );
    }

    pub fn len(&self) -> u32 {
        self.lock().len() as u32
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<i32, PackageEntry>> {
        self.entries
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl Default for UidPackageCache {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests;

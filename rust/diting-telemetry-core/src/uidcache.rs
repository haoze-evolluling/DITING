//! The attribution caches behind `android/engine/uid_cache.go`.
//!
//! Two memo tables keep the JNI-backed lookups out of the per-flow path:
//!
//! * [`FlowUidCache`] — 5-tuple → owner UID. A hit lives 2 s; a miss (`-1` or any non-positive UID,
//!   which is what the platform returns for "not attributable") lives 500 ms so a freshly started
//!   app is not stuck behind a negative entry. At 1024 entries expired rows are pruned first and the
//!   whole map is dropped only when every row is still live.
//! * [`UidPackageCache`] — UID → package name. A hit lives 60 s; empty names are never stored (the
//!   package may be installed later) and 256 entries reset the map (the Go cache did not prune).
//!
//! The flow key keeps the address *wire length*: Go keyed on `netip.Addr`, so a 16-byte IPv4-mapped
//! address and its 4-byte form were different flows. Ports and the protocol are truncated to the Go
//! key's `uint16` / `uint8` widths, which is what the old struct assignment did.
//!
//! Time is injected (`now_ns`): the kernel never reads a clock, so positive/negative expiry, prune
//! and reset are all reachable from tests without sleeping.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

/// `flowUIDCacheTTL`.
pub const FLOW_UID_CACHE_TTL_NS: i64 = 2_000_000_000;
/// `flowUIDNegativeCacheTTL`.
pub const FLOW_UID_NEGATIVE_CACHE_TTL_NS: i64 = 500_000_000;
/// `flowUIDCacheMaxEntries`.
pub const FLOW_UID_CACHE_MAX_ENTRIES: usize = 1024;
/// `uidPackageCacheTTL`.
pub const UID_PACKAGE_CACHE_TTL_NS: i64 = 60_000_000_000;
/// `uidPackageCacheMaxEntries`.
pub const UID_PACKAGE_CACHE_MAX_ENTRIES: usize = 256;

/// One end of a flow, tagged with the byte width Go's `netip.Addr` carried.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Addr {
    V4([u8; 4]),
    V6([u8; 16]),
}

impl Addr {
    /// A `net.IP` slice is accepted only in its 4- or 16-byte form; anything else made the Go cache
    /// bypass itself (`netip.AddrFromSlice` fails), so it must fail here too.
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

/// `flowUIDKey`: both peers, both ports and the transport protocol.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FlowKey {
    pub app: Addr,
    pub server: Addr,
    pub app_port: u16,
    pub server_port: u16,
    pub protocol: u8,
}

impl FlowKey {
    /// Builds the key with the Go struct's field widths (`uint16` ports, `uint8` protocol).
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

/// `cachingUIDResolver`'s table.
pub struct FlowUidCache {
    entries: Mutex<HashMap<FlowKey, FlowEntry>>,
}

impl FlowUidCache {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// `resolveFlow`'s cache lookup: a live entry answers, an expired one is a miss (it stays in the
    /// map until it is overwritten or pruned, exactly like the Go map).
    pub fn lookup(&self, key: &FlowKey, now_ns: i64) -> Option<i32> {
        let entries = self.lock();
        entries
            .get(key)
            .filter(|entry| now_ns < entry.expires_ns)
            .map(|entry| entry.uid)
    }

    /// `resolveFlow`'s insert: negative answers get the short TTL; at capacity expired entries are
    /// pruned and the map is reset only when every entry is still live.
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

    /// Current entry count (expired entries included, like the Go map length).
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

/// `cachingAppUidResolver`'s table.
pub struct UidPackageCache {
    entries: Mutex<HashMap<i32, PackageEntry>>,
}

impl UidPackageCache {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// `PackageForUid`'s cache lookup.
    pub fn lookup(&self, uid: i32, now_ns: i64) -> Option<String> {
        let entries = self.lock();
        entries
            .get(&uid)
            .filter(|entry| now_ns < entry.expires_ns)
            .map(|entry| entry.name.clone())
    }

    /// `PackageForUid`'s insert: empty names are not cached, and 256 entries reset the map.
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

    /// Current entry count (expired entries included).
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

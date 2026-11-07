//! The allowlist state: allowed-domain sets per UID and TTL-bounded IP grants.

use std::collections::{HashMap, HashSet};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use diting_go_compat::ip::{equals_ipv4_zero, equals_ipv6_zero, go_ip_string, is_loopback};

use crate::domain::{domain_matches, normalize_entry, normalize_query_name};

/// `rememberAppAllowlistResponse` prunes expired entries once a UID holds more than this many.
pub const MAX_GRANTS: usize = 256;

#[derive(Default)]
struct State {
    /// UID -> normalized allowed domains. A UID with an empty set is *selected*: it may resolve
    /// nothing and may connect nowhere (the Go code kept the same distinction).
    domains: HashMap<i32, HashSet<String>>,
    /// UID -> IP text -> unix-nanosecond expiry.
    ips: HashMap<i32, HashMap<String, i64>>,
}

/// One resolver-wide allowlist state. The engine owns one instance for its lifetime.
#[derive(Default)]
pub struct AllowlistKernel {
    state: RwLock<State>,
}

impl AllowlistKernel {
    pub fn new() -> Self {
        Self::default()
    }

    /// `SetAppAllowlist`: replace the domain sets with `(uid, raw domains)` entries and drop every
    /// IP grant. Entries are normalized here; a later entry for the same UID replaces the earlier
    /// one, mirroring the Go `rules[uid] = domMap` assignment.
    pub fn configure(&self, entries: &[(i32, Vec<String>)]) {
        let mut domains: HashMap<i32, HashSet<String>> = HashMap::with_capacity(entries.len());
        for (uid, raw_domains) in entries {
            let mut set = HashSet::with_capacity(raw_domains.len());
            for raw in raw_domains {
                if let Some(domain) = normalize_entry(raw) {
                    set.insert(domain);
                }
            }
            domains.insert(*uid, set);
        }

        let mut state = self.write();
        state.domains = domains;
        state.ips.clear();
    }

    /// `hasAppAllowlistUIDs`: any UID at all is under strict mode.
    pub fn has_uids(&self) -> bool {
        !self.read().domains.is_empty()
    }

    /// `appAllowlistDomainAllowed`: an unselected UID may resolve anything; a selected UID only
    /// what its set covers (an empty set covers nothing).
    pub fn domain_allowed(&self, uid: i32, domain: &str) -> bool {
        let state = self.read();
        match state.domains.get(&uid) {
            None => true,
            Some(allowed) => domain_matches(allowed, domain),
        }
    }

    /// `appAllowlistConnectionAllowed`: loopback is always allowed, an unselected UID may connect
    /// anywhere, and a selected UID needs a live grant for this address.
    pub fn connection_allowed(&self, uid: i32, address: &[u8], now_ns: i64) -> bool {
        if is_loopback(address) {
            return true;
        }
        let state = self.read();
        if !state.domains.contains_key(&uid) {
            return true;
        }
        let key = go_ip_string(address);
        state
            .ips
            .get(&uid)
            .and_then(|grants| grants.get(&key))
            .is_some_and(|expiry| now_ns < *expiry)
    }

    /// `rememberAppAllowlistResponse`: grant the live A/AAAA records of one answer to every UID
    /// whose allowlist covers the question (or to the answering UID when the question is empty).
    ///
    /// `records` are `(address bytes, TTL seconds)`; zero TTL, unspecified addresses and empty
    /// addresses never grant anything, exactly like the Go filter.
    pub fn remember(&self, uid: i32, question_name: &str, records: &[(Vec<u8>, u32)], now_ns: i64) {
        if records.is_empty() {
            return;
        }
        let question = normalize_query_name(question_name);

        let mut state = self.write();
        let mut targets: Vec<i32> = Vec::new();
        for (target_uid, allowed) in &state.domains {
            if !question.is_empty() {
                if domain_matches(allowed, &question) {
                    targets.push(*target_uid);
                }
            } else if *target_uid == uid {
                targets.push(*target_uid);
            }
        }
        if targets.is_empty() {
            return;
        }

        for (address, ttl) in records {
            if *ttl == 0 || address.is_empty() {
                continue;
            }
            if equals_ipv4_zero(address) || equals_ipv6_zero(address) {
                continue;
            }
            let key = go_ip_string(address);
            let expiry =
                now_ns.saturating_add((u64::from(*ttl) as i64).saturating_mul(1_000_000_000));
            for target_uid in &targets {
                let grants = state.ips.entry(*target_uid).or_default();
                grants.insert(key.clone(), expiry);
                if grants.len() > MAX_GRANTS {
                    // `now.After(exp)` in Go deletes anything whose expiry is already behind.
                    grants.retain(|_, grant_expiry| *grant_expiry >= now_ns);
                }
            }
        }
    }

    /// Number of stored grants for a UID (the old test's `len(ips[uid])`).
    pub fn grant_count(&self, uid: i32) -> u32 {
        self.read()
            .ips
            .get(&uid)
            .map_or(0, |grants| grants.len() as u32)
    }

    fn read(&self) -> RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests;

use std::collections::{HashMap, HashSet};
use std::net::IpAddr;
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use diting_desktop_api::config::{ClientConfig, DurationValue};
use tokio::sync::Semaphore;

use super::group::{normalize_ip, GroupResolver};
use super::ClientInfo;

pub const MAX_CLIENT_STATS: usize = 4096;
pub const MAX_CLIENT_CACHE: usize = 4096;
pub const MAX_CONCURRENT_RDNS: usize = 16;
pub const DEFAULT_CACHE_TTL_MS: i64 = 3_600_000;
const NEGATIVE_CACHE_MAX_MS: i64 = 5 * 60 * 1000;

pub fn cache_ttl_millis(value: DurationValue) -> i64 {
    let nanos = value.as_nanos();
    if nanos <= 0 {
        DEFAULT_CACHE_TTL_MS
    } else {
        nanos / 1_000_000
    }
}

#[derive(Debug, Clone)]
struct CacheEntry {
    name: String,
    expires_ms: i64,
    stored_ms: i64,
}

#[derive(Debug, Clone)]
struct StatEntry {
    name: String,
    last_seen_ms: i64,
    query_count: u64,
}

struct State {
    enabled: bool,
    enable_rdns: bool,
    cache_ttl_ms: i64,
    aliases: HashMap<IpAddr, String>,
    cache: HashMap<IpAddr, CacheEntry>,
    stats: HashMap<IpAddr, StatEntry>,
    in_flight: HashSet<IpAddr>,
    groups: GroupResolver,
}

pub struct ClientDirectory {
    state: RwLock<State>,
    semaphore: Semaphore,
}

impl ClientDirectory {
    pub fn new(config: &ClientConfig) -> Self {
        let (groups, _) = GroupResolver::new(&config.groups, config.groups_enabled);
        Self {
            state: RwLock::new(State {
                enabled: config.enabled,
                enable_rdns: config.enable_rdns,
                cache_ttl_ms: cache_ttl_millis(config.cache_ttl),
                aliases: compile_aliases(config),
                cache: HashMap::new(),
                stats: HashMap::new(),
                in_flight: HashSet::new(),
                groups,
            }),
            semaphore: Semaphore::new(MAX_CONCURRENT_RDNS),
        }
    }

    pub fn configure(&self, config: &ClientConfig) -> Vec<String> {
        let (groups, diagnostics) = GroupResolver::new(&config.groups, config.groups_enabled);
        let aliases = compile_aliases(config);

        let mut state = self.write();
        state.enabled = config.enabled;
        state.enable_rdns = config.enable_rdns;
        if config.cache_ttl.as_nanos() > 0 {
            state.cache_ttl_ms = cache_ttl_millis(config.cache_ttl);
        }
        state.aliases = aliases;
        state.groups = groups;
        diagnostics
    }

    pub fn enabled(&self) -> bool {
        self.read().enabled
    }

    pub fn identify(&self, ip: IpAddr) -> String {
        let ip = normalize_ip(ip);
        let now = now_ms();
        let mut state = self.write();

        record_activity(&mut state, ip, now);

        if let Some(alias) = state.aliases.get(&ip).cloned() {
            set_stat_name(&mut state, ip, &alias);
            return alias;
        }
        if !state.enabled {
            return String::new();
        }
        if ip.is_loopback() {
            let name = "localhost".to_string();
            set_stat_name(&mut state, ip, &name);
            return name;
        }

        if let Some(entry) = state.cache.get(&ip).cloned() {
            if !entry.name.is_empty() {
                set_stat_name(&mut state, ip, &entry.name);
                return entry.name;
            }
        }
        String::new()
    }

    pub fn lookup_name(&self, ip: IpAddr) -> String {
        let ip = normalize_ip(ip);
        let state = self.read();

        if let Some(alias) = state.aliases.get(&ip) {
            return alias.clone();
        }
        if !state.enabled {
            return String::new();
        }
        if ip.is_loopback() {
            return "localhost".to_string();
        }
        state
            .cache
            .get(&ip)
            .map(|entry| entry.name.clone())
            .unwrap_or_default()
    }

    pub fn group(&self, ip: IpAddr) -> String {
        self.read().groups.resolve(ip)
    }

    pub fn info(&self) -> Vec<ClientInfo> {
        let state = self.read();
        let mut result = Vec::with_capacity(state.stats.len() + state.aliases.len());
        let mut seen = HashSet::with_capacity(state.stats.len());

        for (ip, stat) in &state.stats {
            let name = if stat.name.is_empty() {
                state.aliases.get(ip).cloned().unwrap_or_default()
            } else {
                stat.name.clone()
            };
            result.push(ClientInfo {
                ip: *ip,
                name,
                group: state.groups.resolve(*ip),
                last_seen_ms: stat.last_seen_ms,
                query_count: stat.query_count,
            });
            seen.insert(*ip);
        }

        for (ip, alias) in &state.aliases {
            if seen.contains(ip) {
                continue;
            }
            result.push(ClientInfo {
                ip: *ip,
                name: alias.clone(),
                group: state.groups.resolve(*ip),
                last_seen_ms: 0,
                query_count: 0,
            });
        }

        result.sort_by(|left, right| {
            right
                .last_seen_ms
                .cmp(&left.last_seen_ms)
                .then_with(|| left.ip.cmp(&right.ip))
        });
        result
    }

    pub async fn resolve_reverse(&self, ip: IpAddr) -> Option<String> {
        let ip = normalize_ip(ip);
        let now = now_ms();

        {
            let state = self.read();
            if !state.enable_rdns {
                return None;
            }
            if let Some(entry) = state.cache.get(&ip) {
                if entry.expires_ms > now {
                    return if entry.name.is_empty() {
                        None
                    } else {
                        Some(entry.name.clone())
                    };
                }
            }
        }

        let permit = match self.semaphore.try_acquire() {
            Ok(permit) => permit,
            Err(_) => return None,
        };

        {
            let mut state = self.write();
            if !state.in_flight.insert(ip) {
                return state
                    .cache
                    .get(&ip)
                    .filter(|entry| !entry.name.is_empty())
                    .map(|entry| entry.name.clone());
            }
        }

        let result = tokio::task::spawn_blocking(move || dns_lookup::lookup_addr(&ip).ok())
            .await
            .ok()
            .flatten()
            .map(|name| name.trim_end_matches('.').to_string())
            .filter(|name| !name.is_empty());

        let now = now_ms();
        {
            let mut state = self.write();
            state.in_flight.remove(&ip);
            let ttl = if result.is_some() {
                state.cache_ttl_ms
            } else {
                state.cache_ttl_ms.min(NEGATIVE_CACHE_MAX_MS)
            };
            let name = result.clone().unwrap_or_default();
            insert_cache(&mut state, ip, name.clone(), now, ttl);
            if !name.is_empty() {
                set_stat_name(&mut state, ip, &name);
            }
        }

        drop(permit);
        result
    }

    pub fn alias(&self, ip: IpAddr) -> Option<String> {
        self.read().aliases.get(&normalize_ip(ip)).cloned()
    }

    pub fn last_seen(&self, ip: IpAddr) -> Option<i64> {
        self.read()
            .stats
            .get(&normalize_ip(ip))
            .map(|stat| stat.last_seen_ms)
    }

    pub fn query_count(&self, ip: IpAddr) -> u64 {
        self.read()
            .stats
            .get(&normalize_ip(ip))
            .map(|stat| stat.query_count)
            .unwrap_or(0)
    }

    fn read(&self) -> RwLockReadGuard<'_, State> {
        self.state
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

fn compile_aliases(config: &ClientConfig) -> HashMap<IpAddr, String> {
    let mut aliases = HashMap::new();
    for alias in &config.aliases {
        let name = alias.name.trim();
        if name.is_empty() {
            continue;
        }
        let Ok(ip) = alias.ip.trim().parse::<IpAddr>() else {
            continue;
        };
        aliases
            .entry(normalize_ip(ip))
            .or_insert_with(|| name.to_string());
    }
    aliases
}

fn record_activity(state: &mut State, ip: IpAddr, now: i64) {
    if let Some(stat) = state.stats.get_mut(&ip) {
        stat.query_count = stat.query_count.saturating_add(1);
        stat.last_seen_ms = now;
        return;
    }

    if state.stats.len() >= MAX_CLIENT_STATS {
        if let Some(oldest) = state
            .stats
            .iter()
            .min_by_key(|(_, stat)| stat.last_seen_ms)
            .map(|(ip, _)| *ip)
        {
            state.stats.remove(&oldest);
        }
    }

    state.stats.insert(
        ip,
        StatEntry {
            name: String::new(),
            last_seen_ms: now,
            query_count: 1,
        },
    );
}

fn set_stat_name(state: &mut State, ip: IpAddr, name: &str) {
    if let Some(stat) = state.stats.get_mut(&ip) {
        stat.name = name.to_string();
    }
}

fn insert_cache(state: &mut State, ip: IpAddr, name: String, now: i64, ttl_ms: i64) {
    if state.cache.len() >= MAX_CLIENT_CACHE && !state.cache.contains_key(&ip) {
        let expired = state
            .cache
            .iter()
            .filter(|(_, entry)| entry.expires_ms <= now)
            .min_by_key(|(_, entry)| entry.stored_ms)
            .map(|(ip, _)| *ip);
        let victim = expired.or_else(|| {
            state
                .cache
                .iter()
                .min_by_key(|(_, entry)| entry.stored_ms)
                .map(|(ip, _)| *ip)
        });
        if let Some(victim) = victim {
            state.cache.remove(&victim);
        }
    }

    state.cache.insert(
        ip,
        CacheEntry {
            name,
            expires_ms: now.saturating_add(ttl_ms),
            stored_ms: now,
        },
    );
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}

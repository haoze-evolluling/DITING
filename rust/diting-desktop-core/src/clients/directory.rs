use std::collections::{HashMap, HashSet};
use std::net::IpAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use diting_desktop_api::config::{ClientConfig, DurationValue};
use tokio::sync::{mpsc, Notify, Semaphore};

use super::group::{normalize_ip, GroupResolver};
use super::ClientInfo;

pub const MAX_CLIENT_STATS: usize = 4096;
pub const MAX_CLIENT_CACHE: usize = 4096;
pub const MAX_CONCURRENT_RDNS: usize = 16;
pub const DEFAULT_CACHE_TTL_MS: i64 = 3_600_000;
const NEGATIVE_CACHE_MAX_MS: i64 = 5 * 60 * 1000;
const ACTIVITY_QUEUE_CAPACITY: usize = 8192;
const AGGREGATOR_COALESCE: Duration = Duration::from_millis(50);

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

/// 查询热路径只读的配置快照，仅在 `configure()` 时整体替换。
struct ConfigSnapshot {
    enabled: bool,
    enable_rdns: bool,
    cache_ttl_ms: i64,
    aliases: HashMap<IpAddr, String>,
    groups: GroupResolver,
}

/// 客户端活跃统计的后台聚合器：
/// 热路径只往无锁有界通道塞 `(IpAddr, seen_ms)`，绝不抢全局写锁；
/// 后台任务按批聚合后发布只读 `Arc` 快照，冷路径（UI/诊断）也可按需立即排空。
struct StatsAggregator {
    rx: Mutex<mpsc::Receiver<(IpAddr, i64)>>,
    table: Mutex<HashMap<IpAddr, StatEntry>>,
    snapshot: RwLock<Arc<HashMap<IpAddr, StatEntry>>>,
    pending: AtomicBool,
    closed: AtomicBool,
    started: AtomicBool,
    notify: Notify,
}

impl StatsAggregator {
    fn new(rx: mpsc::Receiver<(IpAddr, i64)>) -> Self {
        Self {
            rx: Mutex::new(rx),
            table: Mutex::new(HashMap::new()),
            snapshot: RwLock::new(Arc::new(HashMap::new())),
            pending: AtomicBool::new(false),
            closed: AtomicBool::new(false),
            started: AtomicBool::new(false),
            notify: Notify::new(),
        }
    }

    fn ensure_worker(self: &Arc<Self>) {
        if self.started.load(Ordering::Relaxed) {
            return;
        }
        let Ok(handle) = tokio::runtime::Handle::try_current() else {
            return;
        };
        if !self.started.swap(true, Ordering::AcqRel) {
            let worker = Arc::clone(self);
            handle.spawn(async move {
                worker.run().await;
            });
        }
    }

    fn record(self: &Arc<Self>, tx: &mpsc::Sender<(IpAddr, i64)>, ip: IpAddr, seen_ms: i64) {
        self.ensure_worker();
        match tx.try_send((ip, seen_ms)) {
            Ok(()) => {
                if !self.pending.swap(true, Ordering::AcqRel) {
                    self.notify.notify_one();
                }
            }
            Err(mpsc::error::TrySendError::Full(item)) => {
                // 无 tokio 运行时（同步单测）时现场排空，避免丢事件；
                // 线上后台聚合器在跑时队列打满宁可丢弃统计，也不阻塞 DNS 热路径。
                if !self.started.load(Ordering::Acquire) {
                    self.drain_now();
                    let _ = tx.try_send(item);
                }
            }
            Err(mpsc::error::TrySendError::Closed(_)) => {}
        }
    }

    fn set_resolved_name(&self, ip: IpAddr, name: &str) {
        self.drain_now();
        let mut table = self.table.lock().unwrap_or_else(|error| error.into_inner());
        let Some(stat) = table.get_mut(&ip) else {
            return;
        };
        if stat.name == name {
            return;
        }
        stat.name = name.to_string();
        let next = Arc::new(table.clone());
        drop(table);
        *self
            .snapshot
            .write()
            .unwrap_or_else(|error| error.into_inner()) = next;
    }

    async fn run(self: Arc<Self>) {
        while !self.closed.load(Ordering::Acquire) {
            self.notify.notified().await;
            if self.closed.load(Ordering::Acquire) {
                break;
            }
            tokio::time::sleep(AGGREGATOR_COALESCE).await;
            self.drain_now();
        }
    }

    fn drain_now(&self) {
        self.pending.store(false, Ordering::Release);
        let mut batch = Vec::new();
        {
            let mut rx = self.rx.lock().unwrap_or_else(|error| error.into_inner());
            while let Ok(item) = rx.try_recv() {
                batch.push(item);
            }
        }
        if batch.is_empty() {
            return;
        }
        let mut table = self.table.lock().unwrap_or_else(|error| error.into_inner());
        for (ip, seen_ms) in batch {
            record_activity(&mut table, ip, seen_ms);
        }
        let next = Arc::new(table.clone());
        drop(table);
        *self
            .snapshot
            .write()
            .unwrap_or_else(|error| error.into_inner()) = next;
    }

    fn snapshot(&self) -> Arc<HashMap<IpAddr, StatEntry>> {
        self.drain_now();
        self.snapshot
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }
}

pub struct ClientDirectory {
    config: RwLock<Arc<ConfigSnapshot>>,
    cache: RwLock<HashMap<IpAddr, CacheEntry>>,
    in_flight: Mutex<HashSet<IpAddr>>,
    activity_tx: mpsc::Sender<(IpAddr, i64)>,
    aggregator: Arc<StatsAggregator>,
    semaphore: Semaphore,
}

impl Drop for ClientDirectory {
    fn drop(&mut self) {
        self.aggregator.closed.store(true, Ordering::Release);
        self.aggregator.notify.notify_one();
    }
}

impl ClientDirectory {
    pub fn new(config: &ClientConfig) -> Self {
        let (groups, _) = GroupResolver::new(&config.groups, config.groups_enabled);
        let (activity_tx, activity_rx) = mpsc::channel(ACTIVITY_QUEUE_CAPACITY);
        let aggregator = Arc::new(StatsAggregator::new(activity_rx));
        aggregator.ensure_worker();
        Self {
            config: RwLock::new(Arc::new(ConfigSnapshot {
                enabled: config.enabled,
                enable_rdns: config.enable_rdns,
                cache_ttl_ms: cache_ttl_millis(config.cache_ttl),
                aliases: compile_aliases(config),
                groups,
            })),
            cache: RwLock::new(HashMap::new()),
            in_flight: Mutex::new(HashSet::new()),
            activity_tx,
            aggregator,
            semaphore: Semaphore::new(MAX_CONCURRENT_RDNS),
        }
    }

    pub fn configure(&self, config: &ClientConfig) -> Vec<String> {
        let (groups, diagnostics) = GroupResolver::new(&config.groups, config.groups_enabled);
        let aliases = compile_aliases(config);

        let mut slot = self
            .config
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let cache_ttl_ms = if config.cache_ttl.as_nanos() > 0 {
            cache_ttl_millis(config.cache_ttl)
        } else {
            slot.cache_ttl_ms
        };
        *slot = Arc::new(ConfigSnapshot {
            enabled: config.enabled,
            enable_rdns: config.enable_rdns,
            cache_ttl_ms,
            aliases,
            groups,
        });
        diagnostics
    }

    pub fn enabled(&self) -> bool {
        self.config_snapshot().enabled
    }

    pub fn identify(&self, ip: IpAddr) -> String {
        let ip = normalize_ip(ip);
        let now = now_ms();
        self.aggregator.record(&self.activity_tx, ip, now);

        let config = self.config_snapshot();
        if let Some(alias) = config.aliases.get(&ip) {
            return alias.clone();
        }
        if !config.enabled {
            return String::new();
        }
        if ip.is_loopback() {
            return "localhost".to_string();
        }
        self.cache_read()
            .get(&ip)
            .filter(|entry| !entry.name.is_empty())
            .map(|entry| entry.name.clone())
            .unwrap_or_default()
    }

    pub fn lookup_name(&self, ip: IpAddr) -> String {
        let ip = normalize_ip(ip);
        let config = self.config_snapshot();

        if let Some(alias) = config.aliases.get(&ip) {
            return alias.clone();
        }
        if !config.enabled {
            return String::new();
        }
        if ip.is_loopback() {
            return "localhost".to_string();
        }
        self.cache_read()
            .get(&ip)
            .map(|entry| entry.name.clone())
            .unwrap_or_default()
    }

    pub fn group(&self, ip: IpAddr) -> String {
        self.config_snapshot().groups.resolve(ip)
    }

    pub fn info(&self) -> Vec<ClientInfo> {
        let config = self.config_snapshot();
        let stats = self.aggregator.snapshot();
        let cache = self.cache_read();
        let mut result = Vec::with_capacity(stats.len() + config.aliases.len());
        let mut seen = HashSet::with_capacity(stats.len());

        for (ip, stat) in stats.iter() {
            let name = resolve_display_name(&config, &cache, *ip, &stat.name);
            result.push(ClientInfo {
                ip: *ip,
                name,
                group: config.groups.resolve(*ip),
                last_seen_ms: stat.last_seen_ms,
                query_count: stat.query_count,
            });
            seen.insert(*ip);
        }

        for (ip, alias) in &config.aliases {
            if seen.contains(ip) {
                continue;
            }
            result.push(ClientInfo {
                ip: *ip,
                name: alias.clone(),
                group: config.groups.resolve(*ip),
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
            let config = self.config_snapshot();
            if !config.enable_rdns {
                return None;
            }
        }
        {
            let cache = self.cache_read();
            if let Some(entry) = cache.get(&ip) {
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
            let mut in_flight = self
                .in_flight
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if !in_flight.insert(ip) {
                drop(in_flight);
                return self
                    .cache_read()
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
        let cache_ttl_ms = self.config_snapshot().cache_ttl_ms;
        {
            let mut in_flight = self
                .in_flight
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            in_flight.remove(&ip);
        }
        {
            let mut cache = self.cache_write();
            let ttl = if result.is_some() {
                cache_ttl_ms
            } else {
                cache_ttl_ms.min(NEGATIVE_CACHE_MAX_MS)
            };
            let name = result.clone().unwrap_or_default();
            insert_cache(&mut cache, ip, name, now, ttl);
        }
        if let Some(name) = &result {
            self.aggregator.set_resolved_name(ip, name);
        }

        drop(permit);
        result
    }

    pub fn alias(&self, ip: IpAddr) -> Option<String> {
        self.config_snapshot()
            .aliases
            .get(&normalize_ip(ip))
            .cloned()
    }

    pub fn last_seen(&self, ip: IpAddr) -> Option<i64> {
        self.aggregator
            .snapshot()
            .get(&normalize_ip(ip))
            .map(|stat| stat.last_seen_ms)
    }

    pub fn query_count(&self, ip: IpAddr) -> u64 {
        self.aggregator
            .snapshot()
            .get(&normalize_ip(ip))
            .map(|stat| stat.query_count)
            .unwrap_or(0)
    }

    fn config_snapshot(&self) -> Arc<ConfigSnapshot> {
        self.config
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    fn cache_read(&self) -> RwLockReadGuard<'_, HashMap<IpAddr, CacheEntry>> {
        self.cache
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn cache_write(&self) -> RwLockWriteGuard<'_, HashMap<IpAddr, CacheEntry>> {
        self.cache
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

fn resolve_display_name(
    config: &ConfigSnapshot,
    cache: &HashMap<IpAddr, CacheEntry>,
    ip: IpAddr,
    recorded_name: &str,
) -> String {
    if let Some(alias) = config.aliases.get(&ip) {
        return alias.clone();
    }
    if !config.enabled {
        return String::new();
    }
    if ip.is_loopback() {
        return "localhost".to_string();
    }
    if let Some(entry) = cache.get(&ip) {
        if !entry.name.is_empty() {
            return entry.name.clone();
        }
    }
    recorded_name.to_string()
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

fn record_activity(stats: &mut HashMap<IpAddr, StatEntry>, ip: IpAddr, now: i64) {
    if let Some(stat) = stats.get_mut(&ip) {
        stat.query_count = stat.query_count.saturating_add(1);
        stat.last_seen_ms = stat.last_seen_ms.max(now);
        return;
    }

    if stats.len() >= MAX_CLIENT_STATS {
        if let Some(oldest) = stats
            .iter()
            .min_by_key(|(_, stat)| stat.last_seen_ms)
            .map(|(ip, _)| *ip)
        {
            stats.remove(&oldest);
        }
    }

    stats.insert(
        ip,
        StatEntry {
            name: String::new(),
            last_seen_ms: now,
            query_count: 1,
        },
    );
}

fn insert_cache(
    cache: &mut HashMap<IpAddr, CacheEntry>,
    ip: IpAddr,
    name: String,
    now: i64,
    ttl_ms: i64,
) {
    if cache.len() >= MAX_CLIENT_CACHE && !cache.contains_key(&ip) {
        let expired = cache
            .iter()
            .filter(|(_, entry)| entry.expires_ms <= now)
            .min_by_key(|(_, entry)| entry.stored_ms)
            .map(|(ip, _)| *ip);
        let victim = expired.or_else(|| {
            cache
                .iter()
                .min_by_key(|(_, entry)| entry.stored_ms)
                .map(|(ip, _)| *ip)
        });
        if let Some(victim) = victim {
            cache.remove(&victim);
        }
    }

    cache.insert(
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

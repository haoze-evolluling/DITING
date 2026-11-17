//! Rolling 24-hour, per-hour statistics collector.
//!
//! Port of the former Go service's `internal/querylog/stats.go`. Hour boundaries are computed in local
//! time (`chrono::Local`) because the UI renders wall-clock hours, exactly like Go's
//! `time.Date(..., t.Location())`.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use chrono::{DateTime, Local, LocalResult, TimeZone, Timelike};

use super::types::{
    normalize_status, HourPoint, NameCount, Record, Summary, STATUS_BLOCKED, STATUS_CACHED,
    STATUS_ERROR, STATUS_STALE,
};

/// Rolling statistics window in hours.
pub(crate) const STATS_WINDOW_HOURS: usize = 24;
const STATS_MAX_KEYS_PER_HOUR: usize = 10_000;
const HOUR_MS: i64 = 60 * 60 * 1000;

type Clock = Arc<dyn Fn() -> DateTime<Local> + Send + Sync>;

struct Bucket {
    hour_ms: i64,
    queries: i64,
    blocked: i64,
    cached: i64,
    forwarded: i64,
    errors: i64,
    lat_sum_ms: f64,
    top_domains: HashMap<String, i64>,
    top_blocked: HashMap<String, i64>,
    top_clients: HashMap<String, i64>,
}

impl Bucket {
    fn new(hour_ms: i64) -> Self {
        Self {
            hour_ms,
            queries: 0,
            blocked: 0,
            cached: 0,
            forwarded: 0,
            errors: 0,
            lat_sum_ms: 0.0,
            top_domains: HashMap::new(),
            top_blocked: HashMap::new(),
            top_clients: HashMap::new(),
        }
    }

    fn counters(&self) -> &HashMap<String, i64> {
        &self.top_domains
    }

    fn blocked_counters(&self) -> &HashMap<String, i64> {
        &self.top_blocked
    }

    fn client_counters(&self) -> &HashMap<String, i64> {
        &self.top_clients
    }
}

#[derive(Clone, Copy)]
enum TopKind {
    Domains,
    Blocked,
    Clients,
}

fn inc_map(map: &mut HashMap<String, i64>, key: &str) {
    if key.is_empty() {
        return;
    }
    if !map.contains_key(key) && map.len() >= STATS_MAX_KEYS_PER_HOUR {
        return;
    }
    *map.entry(key.to_string()).or_insert(0) += 1;
}

/// Normalize a Unix-millisecond timestamp to the start of its local-time hour.
pub(crate) fn hour_key(ms: i64) -> i64 {
    let local = match Local.timestamp_millis_opt(ms) {
        LocalResult::Single(dt) => dt,
        LocalResult::Ambiguous(dt, _) => dt,
        LocalResult::None => return ms,
    };
    let naive = local.naive_local();
    let Some(hour_start) = naive.date().and_hms_opt(naive.time().hour(), 0, 0) else {
        return ms;
    };
    match Local.from_local_datetime(&hour_start) {
        LocalResult::Single(dt) => dt.timestamp_millis(),
        LocalResult::Ambiguous(dt, _) => dt.timestamp_millis(),
        LocalResult::None => ms,
    }
}

/// Thread-safe 24-hour rolling statistics collector.
pub struct Collector {
    buckets: RwLock<HashMap<i64, Bucket>>,
    now: Clock,
}

impl Collector {
    /// Create a collector using the system clock.
    pub fn new() -> Self {
        Self::with_clock(Arc::new(Local::now))
    }

    pub(crate) fn with_clock(now: Clock) -> Self {
        Self {
            buckets: RwLock::new(HashMap::new()),
            now,
        }
    }

    fn now_millis(&self) -> i64 {
        (self.now)().timestamp_millis()
    }

    /// Count one record into its hour bucket and evict buckets outside the rolling window.
    pub fn record(&self, record: &Record) {
        if record.timestamp <= 0 {
            return;
        }
        let key = hour_key(record.timestamp);
        let now = self.now_millis();
        let mut buckets = self.buckets.write().unwrap_or_else(|e| e.into_inner());

        if let std::collections::hash_map::Entry::Vacant(entry) = buckets.entry(key) {
            entry.insert(Bucket::new(key));
            Self::evict_locked(&mut buckets, now);
        }

        let Some(bucket) = buckets.get_mut(&key) else {
            return;
        };
        bucket.queries += 1;
        bucket.lat_sum_ms += record.duration_ms;

        match normalize_status(&record.status) {
            STATUS_BLOCKED => bucket.blocked += 1,
            STATUS_CACHED | STATUS_STALE => bucket.cached += 1,
            STATUS_ERROR => bucket.errors += 1,
            _ => {
                if !record.blocked {
                    bucket.forwarded += 1;
                }
            }
        }
        if record.blocked && normalize_status(&record.status) != STATUS_BLOCKED {
            bucket.blocked += 1;
        }

        inc_map(&mut bucket.top_domains, &record.domain);
        if record.blocked {
            inc_map(&mut bucket.top_blocked, &record.domain);
        }
        let client = if record.client_name.is_empty() {
            &record.client_ip
        } else {
            &record.client_name
        };
        inc_map(&mut bucket.top_clients, client);
    }

    fn evict_locked(buckets: &mut HashMap<i64, Bucket>, now_ms: i64) {
        if buckets.len() <= STATS_WINDOW_HOURS + 1 {
            return;
        }
        let cutoff = hour_key(now_ms - (STATS_WINDOW_HOURS as i64 + 1) * HOUR_MS);
        buckets.retain(|&key, _| key >= cutoff);
    }

    fn window_buckets<'a>(
        &self,
        buckets: &'a HashMap<i64, Bucket>,
        now_ms: i64,
    ) -> Vec<&'a Bucket> {
        let cutoff = hour_key(now_ms - (STATS_WINDOW_HOURS as i64 - 1) * HOUR_MS);
        buckets
            .iter()
            .filter(|(&key, _)| key >= cutoff)
            .map(|(_, bucket)| bucket)
            .collect()
    }

    /// Summary for the current rolling 24-hour window.
    pub fn summary(&self) -> Summary {
        let now = self.now_millis();
        let buckets = self.buckets.read().unwrap_or_else(|e| e.into_inner());
        let mut summary = Summary::default();
        let mut lat_sum = 0.0f64;
        for bucket in self.window_buckets(&buckets, now) {
            summary.queries += bucket.queries;
            summary.blocked += bucket.blocked;
            summary.cached += bucket.cached;
            summary.forwarded += bucket.forwarded;
            summary.errors += bucket.errors;
            lat_sum += bucket.lat_sum_ms;
        }
        if summary.queries > 0 {
            summary.avg_response_ms = lat_sum / summary.queries as f64;
            let denom = summary.queries - summary.errors;
            summary.cache_hit_rate = if denom > 0 {
                summary.cached as f64 / denom as f64
            } else {
                summary.cached as f64 / summary.queries as f64
            };
        }
        summary
    }

    /// One point per hour for the last 24 hours, zero-filled.
    pub fn per_hour(&self) -> Vec<HourPoint> {
        let now = self.now_millis();
        let buckets = self.buckets.read().unwrap_or_else(|e| e.into_inner());
        let mut by_key: HashMap<i64, &Bucket> = HashMap::new();
        for bucket in self.window_buckets(&buckets, now) {
            by_key.insert(bucket.hour_ms, bucket);
        }

        let start = hour_key(now - (STATS_WINDOW_HOURS as i64 - 1) * HOUR_MS);
        let mut points = Vec::with_capacity(STATS_WINDOW_HOURS);
        for index in 0..STATS_WINDOW_HOURS {
            let key = start + index as i64 * HOUR_MS;
            let mut point = HourPoint {
                hour_ms: key,
                ..HourPoint::default()
            };
            if let Some(bucket) = by_key.get(&key) {
                point.queries = bucket.queries;
                point.blocked = bucket.blocked;
                point.cached = bucket.cached;
            }
            points.push(point);
        }
        points
    }

    /// Most queried domains in the window.
    pub fn top_domains(&self, n: i64) -> Vec<NameCount> {
        self.top_n(n, TopKind::Domains)
    }

    /// Most blocked domains in the window.
    pub fn top_blocked_domains(&self, n: i64) -> Vec<NameCount> {
        self.top_n(n, TopKind::Blocked)
    }

    /// Busiest clients in the window.
    pub fn top_clients(&self, n: i64) -> Vec<NameCount> {
        self.top_n(n, TopKind::Clients)
    }

    fn top_n(&self, n: i64, kind: TopKind) -> Vec<NameCount> {
        if n <= 0 {
            return Vec::new();
        }
        let now = self.now_millis();
        let buckets = self.buckets.read().unwrap_or_else(|e| e.into_inner());
        let mut aggregate: HashMap<String, i64> = HashMap::new();
        for bucket in self.window_buckets(&buckets, now) {
            let counters = match kind {
                TopKind::Domains => bucket.counters(),
                TopKind::Blocked => bucket.blocked_counters(),
                TopKind::Clients => bucket.client_counters(),
            };
            for (name, count) in counters {
                *aggregate.entry(name.clone()).or_insert(0) += count;
            }
        }
        drop(buckets);

        let mut list: Vec<NameCount> = aggregate
            .into_iter()
            .map(|(name, count)| NameCount { name, count })
            .collect();
        list.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.name.cmp(&b.name)));
        list.truncate(n as usize);
        list
    }

    /// Drop every statistics bucket.
    pub fn clear(&self) {
        self.buckets
            .write()
            .unwrap_or_else(|e| e.into_inner())
            .clear();
    }
}

impl Default for Collector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::querylog::STATUS_ALLOWED;
    use chrono::TimeZone;

    fn local_ms(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> i64 {
        Local
            .with_ymd_and_hms(year, month, day, hour, minute, 0)
            .single()
            .expect("local time")
            .timestamp_millis()
    }

    fn collector_at(now: i64) -> Collector {
        let now = Local.timestamp_millis_opt(now).single().expect("local");
        Collector::with_clock(Arc::new(move || now))
    }

    fn record(timestamp: i64, domain: &str, status: &str) -> Record {
        Record {
            timestamp,
            domain: domain.into(),
            status: status.into(),
            ..Record::default()
        }
    }

    #[test]
    fn summary_classification() {
        let now = local_ms(2026, 10, 13, 12, 30);
        let collector = collector_at(now);

        collector.record(&Record {
            duration_ms: 10.0,
            client_ip: "1.1.1.1".into(),
            ..record(now, "a.com", STATUS_ALLOWED)
        });
        collector.record(&Record {
            duration_ms: 1.0,
            client_ip: "1.1.1.1".into(),
            blocked: true,
            ..record(now + 1, "ads.com", STATUS_BLOCKED)
        });
        collector.record(&Record {
            cached: true,
            client_ip: "2.2.2.2".into(),
            ..record(now + 2, "a.com", STATUS_CACHED)
        });
        collector.record(&Record {
            duration_ms: 20.0,
            client_ip: "2.2.2.2".into(),
            ..record(now + 3, "x.com", STATUS_ERROR)
        });

        let summary = collector.summary();
        assert_eq!(summary.queries, 4);
        assert_eq!(summary.blocked, 1);
        assert_eq!(summary.cached, 1);
        assert_eq!(summary.errors, 1);
        assert_eq!(summary.forwarded, 1);
        assert!(summary.cache_hit_rate > 0.0);
    }

    #[test]
    fn top_n_lists() {
        let now = local_ms(2026, 10, 13, 12, 0);
        let collector = collector_at(now);
        for _ in 0..3 {
            collector.record(&Record {
                client_ip: "9.9.9.9".into(),
                ..record(now, "hot.com", STATUS_ALLOWED)
            });
        }
        collector.record(&Record {
            client_ip: "8.8.8.8".into(),
            ..record(now, "cold.com", STATUS_ALLOWED)
        });
        for _ in 0..2 {
            collector.record(&Record {
                client_ip: "9.9.9.9".into(),
                blocked: true,
                ..record(now, "ads.com", STATUS_BLOCKED)
            });
        }

        let top = collector.top_domains(1);
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].name, "hot.com");
        assert_eq!(top[0].count, 3);

        let blocked = collector.top_blocked_domains(1);
        assert_eq!(blocked.len(), 1);
        assert_eq!(blocked[0].name, "ads.com");
        assert_eq!(blocked[0].count, 2);

        let clients = collector.top_clients(1);
        assert_eq!(clients.len(), 1);
        assert_eq!(clients[0].name, "9.9.9.9");
    }

    #[test]
    fn window_eviction_excludes_old_buckets() {
        let now = local_ms(2026, 10, 13, 12, 0);
        let collector = collector_at(now);
        collector.record(&record(now - 26 * HOUR_MS, "old.com", STATUS_ALLOWED));
        collector.record(&record(now, "now.com", STATUS_ALLOWED));

        let summary = collector.summary();
        assert_eq!(summary.queries, 1);
    }

    #[test]
    fn per_hour_pads_to_24_points() {
        let now = local_ms(2026, 10, 13, 12, 0);
        let collector = collector_at(now);
        collector.record(&record(now, "a.com", STATUS_ALLOWED));

        let points = collector.per_hour();
        assert_eq!(points.len(), STATS_WINDOW_HOURS);
        assert_eq!(points.last().expect("last").queries, 1);
        assert_eq!(points.last().expect("last").hour_ms, hour_key(now));
    }

    #[test]
    fn clear_resets_stats() {
        let collector = Collector::new();
        collector.record(&record(
            Local::now().timestamp_millis(),
            "a.com",
            STATUS_ALLOWED,
        ));
        collector.clear();
        assert_eq!(collector.summary().queries, 0);
    }

    #[test]
    fn hour_key_aligns_to_local_hour() {
        let now = local_ms(2026, 10, 13, 12, 34);
        assert_eq!(hour_key(now), local_ms(2026, 10, 13, 12, 0));
    }
}

use super::ruleset::{
    apply_allowlist_only, count_service_rules, service_exists, service_group_exists,
};
use super::schedule::first_active;
use super::state::{Inner, MatcherSnapshot, ScheduleSet};
use super::types::*;

use std::collections::HashSet;
use std::net::IpAddr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use chrono::{Local, TimeZone};
use diting_desktop_api::config::filter::is_valid_block_mode;
use diting_desktop_api::config::{BlockingSchedule, FilterConfig};
use diting_go_compat::text::{go_lower, go_trim_space};
use diting_response_core::chain::plan_strs;

pub const MAX_RESPONSE_ALIAS_DEPTH: usize = 8;

const PERMANENT_PAUSE_MS: i64 = 100 * 365 * 24 * 3600 * 1000;

#[derive(Clone)]
pub struct RuleEngine {
    pub(super) inner: Arc<Inner>,
}

impl RuleEngine {
    pub fn new(config: FilterConfig) -> Self {
        let config = normalize_config(config);
        let engine = Self {
            inner: Arc::new(Inner {
                config: RwLock::new(config.clone()),
                groups: RwLock::new(GroupConfig::default()),
                schedules: RwLock::new(ScheduleSet::default()),
                matchers: RwLock::new(Arc::new(MatcherSnapshot::default())),
                rebuild_lock: Mutex::new(()),
                bogus: RwLock::new(None),
                paused_until_ms: RwLock::new(None),
                total_queries: AtomicU64::new(0),
                blocked_queries: AtomicU64::new(0),
                allowed_queries: AtomicU64::new(0),
                stopped: AtomicBool::new(false),
            }),
        };
        engine
            .inner
            .sync_schedules(&config, &GroupConfig::default());
        engine.inner.sync_bogus(&config);
        engine.inner.rebuild_now();
        engine
    }

    pub fn configure(&self, config: FilterConfig) {
        let old = self.inner.config.read().unwrap().clone();
        let next = normalize_config(config);
        let inputs_changed = !matcher_inputs_equal(&old, &next)
            || self.inner.matchers.read().unwrap().global.total_rules() == 0;

        *self.inner.config.write().unwrap() = next.clone();
        let groups = self.inner.groups.read().unwrap().clone();
        self.inner.sync_schedules(&next, &groups);
        self.inner.sync_bogus(&next);
        if inputs_changed {
            self.inner.rebuild_now();
        }
    }

    pub fn config(&self) -> FilterConfig {
        self.inner.config.read().unwrap().clone()
    }

    pub fn is_enabled(&self) -> bool {
        let now = Local::now();
        self.inner.switch_on() && self.inner.global_schedule_active(&now)
    }

    pub fn paused_until(&self) -> Option<i64> {
        self.inner.pause_state_at(now_ms()).until_ms
    }

    pub fn pause_state(&self) -> PauseState {
        self.inner.pause_state_at(now_ms())
    }

    pub fn set_paused(&self, paused: bool, duration_sec: i64) {
        let until = if !paused {
            None
        } else if duration_sec <= 0 {
            Some(now_ms().saturating_add(PERMANENT_PAUSE_MS))
        } else {
            Some(now_ms().saturating_add(duration_sec.min(MAX_PAUSE_DURATION_SEC) * 1000))
        };
        *self.inner.paused_until_ms.write().unwrap() = until;
    }

    pub fn check(&self, domain: &str, qtype: u16, group: &str) -> CheckHostResult {
        let now = Local::now();
        if !self.inner.switch_on() {
            return CheckHostResult::pass();
        }
        if !self.inner.blocking_active_for_group(group, &now) {
            return CheckHostResult::pass_with_reason(REASON_SCHEDULE_INACTIVE);
        }
        let matcher = self.inner.matcher_for_group(group);
        let domain = normalize_domain(domain);
        if domain.is_empty() {
            return CheckHostResult::pass();
        }

        let mut result = matcher.match_domain(&domain, qtype);
        if self.inner.allowlist_only_for_group(group) {
            result = apply_allowlist_only(result);
        }
        if result.blocked && !self.inner.service_schedule_blocks(&result.list_name, &now) {
            result = CheckHostResult::pass_with_reason(REASON_SERVICE_SCHEDULE_INACTIVE);
        }
        self.record_verdict(&result);
        result
    }

    pub fn check_host(&self, domain: &str, qtype: u16) -> CheckHostResult {
        let domain = normalize_domain(domain);
        if domain.is_empty() {
            return CheckHostResult::pass();
        }
        self.inner
            .matchers
            .read()
            .unwrap()
            .global
            .match_domain(&domain, qtype)
    }

    pub fn record_verdict(&self, result: &CheckHostResult) {
        self.inner.total_queries.fetch_add(1, Ordering::Relaxed);
        if result.blocked {
            self.inner.blocked_queries.fetch_add(1, Ordering::Relaxed);
        } else if result.action == VerdictAction::Allow {
            self.inner.allowed_queries.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub fn check_response(
        &self,
        qname: &str,
        qtype: u16,
        group: &str,
        records: &[ResponseRecord],
    ) -> CheckHostResult {
        let now = Local::now();
        if !self.inner.switch_on() {
            return CheckHostResult::pass();
        }
        if !self.inner.blocking_active_for_group(group, &now) {
            return CheckHostResult::pass_with_reason(REASON_SCHEDULE_INACTIVE);
        }

        let names = extract_response_check_names(qname, records);
        if names.is_empty() {
            return CheckHostResult::pass();
        }
        let plan = plan_strs(names.iter().map(String::as_str), MAX_RESPONSE_ALIAS_DEPTH);
        let matcher = self.inner.matcher_for_group(group);
        for name in &plan.targets {
            let mut result = matcher.match_domain(name, qtype);
            if result.blocked {
                result.reason = REASON_RESPONSE_BLOCKED.to_string();
                return result;
            }
        }
        CheckHostResult::pass()
    }

    pub fn bogus_nxdomain(&self, addresses: &[IpAddr]) -> Option<BogusNxDomainHit> {
        self.inner
            .bogus
            .read()
            .unwrap()
            .as_ref()
            .and_then(|matcher| matcher.hit(addresses))
    }

    pub fn bogus_nxdomain_hits(&self) -> u64 {
        self.inner
            .bogus
            .read()
            .unwrap()
            .as_ref()
            .map_or(0, |matcher| matcher.hits())
    }

    pub fn filter_response_enabled(&self) -> bool {
        self.inner.config.read().unwrap().filter_response
    }

    pub fn stats(&self) -> FilterStats {
        let now = Local::now();
        let (enabled, active_lists) = {
            let config = self.inner.config.read().unwrap();
            (
                config.enabled,
                config.lists.iter().filter(|list| list.enabled).count() as i32,
            )
        };
        let total = self.inner.total_queries.load(Ordering::Relaxed);
        let blocked = self.inner.blocked_queries.load(Ordering::Relaxed);
        let allowed = self.inner.allowed_queries.load(Ordering::Relaxed);
        let total_rules = self.inner.matchers.read().unwrap().global.total_rules();
        let pause = self.inner.pause_state_at(now_ms());

        FilterStats {
            enabled,
            total_rules,
            active_lists,
            total_queries: total,
            blocked_queries: blocked,
            allowed_queries: allowed,
            block_rate: if total == 0 {
                0.0
            } else {
                blocked as f64 / total as f64 * 100.0
            },
            schedule_active: self.inner.global_schedule_active(&now),
            paused: pause.paused,
            paused_remaining_sec: pause.remaining_sec,
            paused_until_ms: pause.until_ms.unwrap_or(0),
        }
    }

    pub fn is_blocking_active(&self) -> bool {
        self.inner.global_schedule_active(&Local::now())
    }

    pub fn is_blocking_active_at(&self, now_ms: i64) -> bool {
        match Local.timestamp_millis_opt(now_ms).single() {
            Some(now) => self.inner.global_schedule_active(&now),
            None => true,
        }
    }

    pub fn is_blocking_active_for_group(&self, group: &str) -> bool {
        self.inner.blocking_active_for_group(group, &Local::now())
    }

    pub fn current_schedule(&self) -> Option<ScheduleView> {
        let config = self.inner.config.read().unwrap();
        if !config.schedule_enabled {
            return None;
        }
        let schedules = self.inner.schedules.read().unwrap();
        first_active(&schedules.global, &Local::now()).map(|schedule| ScheduleView {
            id: schedule.id.clone(),
            name: schedule.name.clone(),
        })
    }

    pub fn set_groups(&self, groups: GroupConfig) {
        let groups = normalize_groups(groups);
        *self.inner.groups.write().unwrap() = groups.clone();
        let config = self.inner.config.read().unwrap().clone();
        self.inner.sync_schedules(&config, &groups);
        self.inner.rebuild_now();
    }

    pub fn groups(&self) -> GroupConfig {
        self.inner.groups.read().unwrap().clone()
    }

    pub fn group_block_mode(&self, group: &str) -> Option<String> {
        self.inner
            .matchers
            .read()
            .unwrap()
            .block_modes
            .get(group)
            .cloned()
    }

    pub fn block_response_config(&self, group: &str) -> BlockResponseConfig {
        let config = self.inner.config.read().unwrap();
        let mode = self
            .group_block_mode(group)
            .unwrap_or_else(|| config.block_mode.clone());
        BlockResponseConfig {
            block_mode: mode,
            blocking_ipv4: config.blocking_ipv4.clone(),
            blocking_ipv6: config.blocking_ipv6.clone(),
        }
    }

    pub fn count_service_rules(&self, service_ids: &[String], group_ids: &[String]) -> usize {
        count_service_rules(service_ids, group_ids)
    }

    pub fn spawn_update_ticker(self: &Arc<Self>, period: Duration) -> tokio::task::JoinHandle<()> {
        let engine = Arc::clone(self);
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(period).await;
                if engine.inner.stopped.load(Ordering::Relaxed) {
                    break;
                }
                let _ = engine.refresh_due().await;
            }
        })
    }

    pub fn close(&self) {
        self.inner.stopped.store(true, Ordering::Relaxed);
    }
}

pub fn extract_response_check_names(qname: &str, records: &[ResponseRecord]) -> Vec<String> {
    let origin = normalize_domain(qname);
    let mut seen = HashSet::new();
    let mut names = Vec::with_capacity(MAX_RESPONSE_ALIAS_DEPTH);

    for record in records {
        let raw = match record.kind {
            ResponseRecordKind::Cname => record.target.as_deref(),
            ResponseRecordKind::A
            | ResponseRecordKind::Aaaa
            | ResponseRecordKind::Https
            | ResponseRecordKind::Svcb => Some(record.owner.as_str()),
            ResponseRecordKind::Other => None,
        };
        let Some(raw) = raw else {
            continue;
        };
        let name = normalize_domain(raw);
        if name.is_empty() || name == origin || !seen.insert(name.clone()) {
            continue;
        }
        if names.len() >= MAX_RESPONSE_ALIAS_DEPTH {
            break;
        }
        names.push(name);
    }
    names
}

fn normalize_config(mut config: FilterConfig) -> FilterConfig {
    config.normalize();
    config.blocked_services.retain(|id| service_exists(id));
    config
        .blocked_service_groups
        .retain(|id| service_group_exists(id));
    config.service_schedules.retain(|id, _| service_exists(id));
    config
}

fn matcher_inputs_equal(a: &FilterConfig, b: &FilterConfig) -> bool {
    a.custom_rules == b.custom_rules
        && a.blocked_services == b.blocked_services
        && a.blocked_service_groups == b.blocked_service_groups
        && a.data_dir == b.data_dir
        && a.lists.len() == b.lists.len()
        && a.lists.iter().zip(&b.lists).all(|(left, right)| {
            left.id == right.id
                && left.url == right.url
                && left.enabled == right.enabled
                && left.name == right.name
        })
}

fn normalize_groups(mut config: GroupConfig) -> GroupConfig {
    let mut seen = HashSet::new();
    let mut groups = Vec::with_capacity(config.groups.len());
    for (index, mut group) in config.groups.into_iter().enumerate() {
        group.id = group.id.trim().to_string();
        group.name = group.name.trim().to_string();
        if group.id.is_empty() {
            group.id = format!("group-{}", index + 1);
        }
        if group.id == DEFAULT_CLIENT_GROUP_ID || !seen.insert(group.id.clone()) {
            continue;
        }
        if group.name.is_empty() {
            group.name = group.id.clone();
        }
        if !group.block_mode.is_empty() && !is_valid_block_mode(&group.block_mode) {
            group.block_mode.clear();
        }
        group.rule_list_ids = dedup_trimmed(group.rule_list_ids);
        group.upstream_ids = dedup_trimmed(group.upstream_ids);
        if !group
            .schedules
            .iter()
            .any(|schedule: &BlockingSchedule| schedule.enabled)
        {
            group.schedule_enabled = false;
        }
        groups.push(group);
    }
    config.groups = groups;
    config
}

fn dedup_trimmed(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    values
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty() && seen.insert(value.clone()))
        .collect()
}

pub fn normalize_domain(domain: &str) -> String {
    let lowered = go_lower(go_trim_space(domain));
    lowered
        .strip_suffix('.')
        .unwrap_or(lowered.as_ref())
        .to_string()
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

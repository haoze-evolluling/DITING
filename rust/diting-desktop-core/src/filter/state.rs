use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64};
use std::sync::{Arc, Mutex, RwLock};

use chrono::{DateTime, Local};
use diting_desktop_api::config::FilterConfig;

use super::cache::ListCache;
use super::engine::now_ms;
use super::schedule::{any_active, compile_all, has_enabled, CompiledSchedule};
use super::types::*;
use super::{bogus, fetch, ruleset};

use bogus::BogusNXDomainMatcher;
use ruleset::{
    expand_services, parse_custom_rules, parse_list_text, CompiledRule, RuleMatcher, RuleSet,
    SERVICE_SOURCE_PREFIX,
};

pub(super) const LIST_STATUS_OK: &str = "ok";
pub(super) const LIST_STATUS_UNCHANGED: &str = "unchanged";
pub(super) const LIST_STATUS_CACHED: &str = "cached";
pub(super) const LIST_STATUS_FAILED: &str = "failed";

pub(super) struct MatcherSnapshot {
    pub(super) global: Arc<RuleMatcher>,
    pub(super) groups: HashMap<String, Arc<RuleMatcher>>,
    pub(super) block_modes: HashMap<String, String>,
}

impl Default for MatcherSnapshot {
    fn default() -> Self {
        Self {
            global: Arc::new(RuleMatcher::build(std::iter::empty())),
            groups: HashMap::new(),
            block_modes: HashMap::new(),
        }
    }
}

#[derive(Debug, Default)]
pub(super) struct ScheduleSet {
    pub(super) global: Vec<CompiledSchedule>,
    groups: HashMap<String, Vec<CompiledSchedule>>,
    services: HashMap<String, Vec<CompiledSchedule>>,
}

pub(super) struct Inner {
    pub(super) config: RwLock<FilterConfig>,
    pub(super) list_cache: Arc<dyn ListCache>,
    pub(super) groups: RwLock<GroupConfig>,
    pub(super) schedules: RwLock<ScheduleSet>,
    pub(super) matchers: RwLock<Arc<MatcherSnapshot>>,
    pub(super) rebuild_lock: Mutex<()>,
    pub(super) bogus: RwLock<Option<Arc<BogusNXDomainMatcher>>>,
    pub(super) paused_until_ms: RwLock<Option<i64>>,
    pub(super) total_queries: AtomicU64,
    pub(super) blocked_queries: AtomicU64,
    pub(super) allowed_queries: AtomicU64,
    pub(super) stopped: AtomicBool,
}

impl Inner {
    pub(super) fn switch_on(&self) -> bool {
        self.config.read().unwrap().enabled && self.pause_state_at(now_ms()).until_ms.is_none()
    }

    pub(super) fn pause_state_at(&self, now: i64) -> PauseState {
        let until = *self.paused_until_ms.read().unwrap();
        let Some(until) = until else {
            return PauseState::default();
        };
        if now >= until {
            PauseState::default()
        } else {
            PauseState {
                paused: true,
                remaining_sec: (until - now) / 1000,
                until_ms: Some(until),
            }
        }
    }

    pub(super) fn global_schedule_active(&self, now: &DateTime<Local>) -> bool {
        let config = self.config.read().unwrap();
        let schedules = self.schedules.read().unwrap();
        if !config.schedule_enabled || !has_enabled(&schedules.global) {
            return true;
        }
        any_active(&schedules.global, now)
    }

    pub(super) fn blocking_active_for_group(&self, group: &str, now: &DateTime<Local>) -> bool {
        let config = self.config.read().unwrap();
        let groups = self.groups.read().unwrap();
        let schedules = self.schedules.read().unwrap();

        if let Some(found) = group_by_id(&groups, group) {
            if found.schedule_enabled {
                if let Some(list) = schedules.groups.get(&found.id) {
                    if has_enabled(list) {
                        return any_active(list, now);
                    }
                }
            }
        }
        if !config.schedule_enabled || !has_enabled(&schedules.global) {
            return true;
        }
        any_active(&schedules.global, now)
    }

    pub(super) fn service_schedule_blocks(&self, source: &str, now: &DateTime<Local>) -> bool {
        let schedules = self.schedules.read().unwrap();
        if schedules.services.is_empty() {
            return true;
        }
        let Some(id) = source.strip_prefix(SERVICE_SOURCE_PREFIX) else {
            return true;
        };
        match schedules.services.get(id.trim()) {
            Some(list) if has_enabled(list) => any_active(list, now),
            _ => true,
        }
    }

    pub(super) fn allowlist_only_for_group(&self, group: &str) -> bool {
        let config = self.config.read().unwrap();
        let groups = self.groups.read().unwrap();
        match group_by_id(&groups, group) {
            Some(found) => found.allowlist_only,
            None => config.allowlist_only,
        }
    }

    pub(super) fn matcher_for_group(&self, group: &str) -> Arc<RuleMatcher> {
        let snapshot = self.matchers.read().unwrap().clone();
        let groups = self.groups.read().unwrap();
        if groups.enabled && !group.is_empty() && group != DEFAULT_CLIENT_GROUP_ID {
            if let Some(matcher) = snapshot.groups.get(group) {
                return Arc::clone(matcher);
            }
        }
        Arc::clone(&snapshot.global)
    }

    pub(super) fn sync_schedules(&self, config: &FilterConfig, groups: &GroupConfig) {
        let mut compiled = ScheduleSet {
            global: compile_all(&config.schedules),
            ..ScheduleSet::default()
        };
        for group in &groups.groups {
            if !group.schedules.is_empty() {
                compiled
                    .groups
                    .insert(group.id.clone(), compile_all(&group.schedules));
            }
        }
        for (id, schedules) in &config.service_schedules {
            compiled.services.insert(id.clone(), compile_all(schedules));
        }
        *self.schedules.write().unwrap() = compiled;
    }

    pub(super) fn sync_bogus(&self, config: &FilterConfig) {
        if !config.enabled || !config.bogus_nx_domain {
            *self.bogus.write().unwrap() = None;
            return;
        }
        let (matcher, _problem) = BogusNXDomainMatcher::new(&config.bogus_nx_domain_networks);
        *self.bogus.write().unwrap() = if matcher.size() == 0 {
            None
        } else {
            Some(Arc::new(matcher))
        };
    }

    pub(super) fn rebuild_now(&self) {
        let _rebuild = self.rebuild_lock.lock().unwrap();
        let config = self.config.read().unwrap().clone();
        let groups = self.groups.read().unwrap().clone();

        let mut rule_set = RuleSet {
            custom: parse_custom_rules(&config.custom_rules),
            service: expand_services(&config.blocked_services, &config.blocked_service_groups),
            ..RuleSet::default()
        };
        let mut counts: Vec<(String, i32)> = Vec::new();
        for list in &config.lists {
            if !list.enabled {
                continue;
            }
            let rules = self
                .list_cache
                .read(&list.id)
                .map(|data| parse_list_text(&String::from_utf8_lossy(&data), &list.id))
                .unwrap_or_default();
            counts.push((list.id.clone(), rules.len() as i32));
            rule_set.lists.extend(rules);
        }

        let global = Arc::new(RuleMatcher::build(
            rule_set.all().into_iter().cloned().collect::<Vec<_>>(),
        ));
        let mut group_matchers = HashMap::new();
        let mut block_modes = HashMap::new();
        if groups.enabled {
            for group in &groups.groups {
                if !group.enabled || group.id.is_empty() || group.id == DEFAULT_CLIENT_GROUP_ID {
                    continue;
                }
                let rules: Vec<CompiledRule> = rule_set
                    .for_group(&group.rule_list_ids)
                    .into_iter()
                    .cloned()
                    .collect();
                group_matchers.insert(group.id.clone(), Arc::new(RuleMatcher::build(rules)));
                if !group.block_mode.is_empty() {
                    block_modes.insert(group.id.clone(), group.block_mode.clone());
                }
            }
        }

        *self.matchers.write().unwrap() = Arc::new(MatcherSnapshot {
            global,
            groups: group_matchers,
            block_modes,
        });

        if !counts.is_empty() {
            let mut stored = self.config.write().unwrap();
            for (id, count) in counts {
                if let Some(list) = stored.lists.iter_mut().find(|list| list.id == id) {
                    list.rules_count = count;
                }
            }
        }
    }

    pub(super) async fn refresh_list_inner(&self, id: &str) -> Result<bool, FilterError> {
        let (url, etag, last_modified) = {
            let config = self.config.read().unwrap();
            let Some(list) = config.lists.iter().find(|list| list.id == id) else {
                return Err(FilterError::ListNotFound(id.to_string()));
            };
            (
                list.url.clone(),
                list.etag.clone(),
                list.last_modified.clone(),
            )
        };

        let outcome = match fetch::fetch_conditional(&url, &etag, &last_modified).await {
            Ok(outcome) => outcome,
            Err(error) => {
                let cached = self.list_cache.read(id).is_some();
                let transient = error.is_transient();
                {
                    let mut config = self.config.write().unwrap();
                    if let Some(list) = config.lists.iter_mut().find(|list| list.id == id) {
                        list.last_status = if cached && transient {
                            LIST_STATUS_CACHED
                        } else {
                            LIST_STATUS_FAILED
                        }
                        .to_string();
                        list.last_error = error.message();
                    }
                }
                if cached && transient {
                    return Ok(false);
                }
                return Err(FilterError::Fetch {
                    url: error.url().to_string(),
                    message: error.message(),
                    transient,
                });
            }
        };

        if outcome.not_modified {
            let mut config = self.config.write().unwrap();
            if let Some(list) = config.lists.iter_mut().find(|list| list.id == id) {
                list.last_status = LIST_STATUS_UNCHANGED.to_string();
                list.last_error.clear();
                list.last_updated = now_ms();
            }
            return Ok(false);
        }

        let data = outcome.data.unwrap_or_default();
        let cache = Arc::clone(&self.list_cache);
        let write_id = id.to_string();
        let write_data = data.clone();
        let write = tokio::task::spawn_blocking(move || cache.write(&write_id, &write_data))
            .await
            .map_err(|error| FilterError::Join(error.to_string()))?;
        if let Err(error) = write {
            let mut config = self.config.write().unwrap();
            if let Some(list) = config.lists.iter_mut().find(|list| list.id == id) {
                list.last_status = LIST_STATUS_FAILED.to_string();
                list.last_error = error.to_string();
            }
            return Err(FilterError::Io(error.to_string()));
        }

        let text = String::from_utf8_lossy(&data);
        let rules_count = parse_list_text(&text, id).len() as i32;
        let checksum = fetch::list_checksum(&data);
        let mut config = self.config.write().unwrap();
        if let Some(list) = config.lists.iter_mut().find(|list| list.id == id) {
            list.rules_count = rules_count;
            list.last_updated = now_ms();
            list.checksum = checksum;
            list.etag = outcome.etag;
            list.last_modified = outcome.last_modified;
            list.last_status = LIST_STATUS_OK.to_string();
            list.last_error.clear();
        }
        Ok(true)
    }
}

fn group_by_id<'a>(groups: &'a GroupConfig, id: &str) -> Option<&'a ClientGroup> {
    if id.is_empty() || id == DEFAULT_CLIENT_GROUP_ID || !groups.enabled {
        return None;
    }
    groups.groups.iter().find(|group| group.id == id)
}

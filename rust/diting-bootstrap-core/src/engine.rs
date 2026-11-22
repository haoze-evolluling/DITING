use std::cmp::Ordering;
use std::collections::HashMap;
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use crate::health::{
    Health, Score, BASE_EXPLORATION_RATE, LOW_SAMPLE_EXPLORATION_RATE, LOW_SAMPLE_THRESHOLD,
    RECOVERY_EXPLORATION_RATE,
};

pub const CACHE_TTL_NS: i64 = 60_000_000_000;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Plan {
    pub primary: Option<usize>,
    pub fallbacks: Vec<usize>,
    pub exploration: bool,
}

struct CacheEntry {
    ip: String,
    expires_ns: i64,
}

#[derive(Default)]
struct State {
    health: HashMap<String, Health>,
    cache: HashMap<String, CacheEntry>,
}

#[derive(Default)]
pub struct BootstrapKernel {
    state: RwLock<State>,
}

impl BootstrapKernel {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn plan(
        &self,
        entries: &[(String, f64)],
        now_ns: i64,
        explore_roll: f64,
        weight_roll: f64,
        index_roll: u64,
    ) -> Plan {
        let count = entries.len();
        if count == 0 {
            return Plan::default();
        }
        if count == 1 {
            return Plan {
                primary: Some(0),
                fallbacks: Vec::new(),
                exploration: false,
            };
        }

        let scores: Vec<Score> = {
            let mut state = self.write();
            entries
                .iter()
                .map(|(id, weight)| health_for(&mut state, id, now_ns).score(*weight, now_ns))
                .collect()
        };

        let mut candidates: Vec<usize> = Vec::with_capacity(count);
        let mut has_cooling_down = false;
        for (index, score) in scores.iter().enumerate() {
            if score.cooling_down {
                has_cooling_down = true;
            } else {
                candidates.push(index);
            }
        }
        let has_low_sample = scores
            .iter()
            .any(|score| score.sample_count < LOW_SAMPLE_THRESHOLD);
        if candidates.is_empty() {
            candidates.extend(0..count);
        }

        let exploration_rate = if has_cooling_down {
            RECOVERY_EXPLORATION_RATE
        } else if has_low_sample {
            LOW_SAMPLE_EXPLORATION_RATE
        } else {
            BASE_EXPLORATION_RATE
        };
        let exploration = explore_roll < exploration_rate;

        let primary = if exploration {
            let length = candidates.len() as u64;
            candidates[(index_roll % length) as usize]
        } else {
            choose_weighted(&candidates, &scores, weight_roll)
        };

        let primary_id = &entries[primary].0;
        let mut remaining: Vec<usize> = (0..count)
            .filter(|index| &entries[*index].0 != primary_id)
            .collect();
        remaining.sort_by(|a, b| {
            scores[*b]
                .weight
                .partial_cmp(&scores[*a].weight)
                .unwrap_or(Ordering::Equal)
        });

        Plan {
            primary: Some(primary),
            fallbacks: remaining,
            exploration,
        }
    }

    pub fn score(&self, id: &str, entry_weight: f64, now_ns: i64) -> Score {
        let mut state = self.write();
        health_for(&mut state, id, now_ns).score(entry_weight, now_ns)
    }

    pub fn record_result(&self, id: &str, success: bool, elapsed_ms: i64, now_ns: i64) {
        let mut state = self.write();
        health_for(&mut state, id, now_ns).record_result(success, elapsed_ms, now_ns);
    }

    pub fn cache_get(&self, host: &str, now_ns: i64) -> Option<String> {
        let state = self.read();
        let entry = state.cache.get(host)?;
        if now_ns > entry.expires_ns {
            return None;
        }
        Some(entry.ip.clone())
    }

    pub fn cache_put(&self, host: &str, ip: &str, now_ns: i64) {
        let mut state = self.write();
        state.cache.insert(
            host.to_string(),
            CacheEntry {
                ip: ip.to_string(),
                expires_ns: now_ns.saturating_add(CACHE_TTL_NS),
            },
        );
    }

    pub fn clear_cache(&self) {
        self.write().cache.clear();
    }

    pub fn reset(&self) {
        let mut state = self.write();
        state.health.clear();
        state.cache.clear();
    }

    pub fn health_count(&self) -> u32 {
        self.read().health.len() as u32
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

fn health_for<'a>(state: &'a mut State, id: &str, now_ns: i64) -> &'a mut Health {
    state
        .health
        .entry(id.to_string())
        .or_insert_with(|| Health::new(now_ns))
}

fn choose_weighted(candidates: &[usize], scores: &[Score], roll: f64) -> usize {
    let total: f64 = candidates
        .iter()
        .filter(|index| scores[**index].weight > 0.0)
        .map(|index| scores[*index].weight)
        .sum();
    if total <= 0.0 {
        return candidates[0];
    }

    let mut remaining = roll * total;
    for index in candidates {
        if scores[*index].weight > 0.0 {
            remaining -= scores[*index].weight;
            if remaining <= 0.0 {
                return *index;
            }
        }
    }
    *candidates
        .last()
        .expect("candidates is non-empty when plan reaches choose_weighted")
}

#[cfg(test)]
mod tests;

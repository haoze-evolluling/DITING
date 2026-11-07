//! The bootstrap kernel state: per-endpoint health, host cache and plan selection.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use crate::health::{
    Health, Score, BASE_EXPLORATION_RATE, LOW_SAMPLE_EXPLORATION_RATE, LOW_SAMPLE_THRESHOLD,
    RECOVERY_EXPLORATION_RATE,
};

/// `putCached` lifetime: one minute.
pub const CACHE_TTL_NS: i64 = 60_000_000_000;

/// The old `bootstrapPlan`: the chosen primary, the fallbacks in weight order, and whether the
/// primary came from exploration rather than from the weighted draw.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Plan {
    /// Index into the entries passed to [`BootstrapKernel::plan`]; `None` for an empty config.
    pub primary: Option<usize>,
    /// Indices into the same entries, sorted by weight descending (stable).
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

/// One bootstrap resolver's kernel state.
#[derive(Default)]
pub struct BootstrapKernel {
    state: RwLock<State>,
}

impl BootstrapKernel {
    pub fn new() -> Self {
        Self::default()
    }

    /// `choosePlan`. `entries` is the config snapshot the caller raced: `(id, weight)` in
    /// configured order. Health is keyed by id and survives a config change, exactly like the Go
    /// `healthMap`.
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

        // The Go code drops every entry whose *id* equals the primary's, not just the primary
        // index, so duplicate ids never show up as fallbacks.
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

    /// `GetScore`: the test-facing form of the old `bootstrapScore`.
    pub fn score(&self, id: &str, entry_weight: f64, now_ns: i64) -> Score {
        let mut state = self.write();
        health_for(&mut state, id, now_ns).score(entry_weight, now_ns)
    }

    /// `RecordResult` on the endpoint's health, creating it at `now_ns` on first use.
    pub fn record_result(&self, id: &str, success: bool, elapsed_ms: i64, now_ns: i64) {
        let mut state = self.write();
        health_for(&mut state, id, now_ns).record_result(success, elapsed_ms, now_ns);
    }

    /// `getCached`: a hit only while `now_ns <= expires_ns` (Go expired with `After`).
    pub fn cache_get(&self, host: &str, now_ns: i64) -> Option<String> {
        let state = self.read();
        let entry = state.cache.get(host)?;
        if now_ns > entry.expires_ns {
            return None;
        }
        Some(entry.ip.clone())
    }

    /// `putCached`: one minute from `now_ns`.
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

    /// `UpdateConfig` clears the host cache but keeps the health history.
    pub fn clear_cache(&self) {
        self.write().cache.clear();
    }

    /// `ResetStats` clears both the health history and the host cache.
    pub fn reset(&self) {
        let mut state = self.write();
        state.health.clear();
        state.cache.clear();
    }

    /// Number of endpoints with a health entry (the old test's `len(healthMap)`).
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

/// `chooseWeighted`: subtract each weight from `roll * total` and take the first one that crosses
/// zero; a non-positive total falls back to the first candidate.
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

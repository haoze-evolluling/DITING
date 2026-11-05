//! Query entry points: normalization, the decision cache and prewarming.
//!
//! Split out of `snapshot.rs` (whose table building and priority walk are already long), but it is
//! the same implementation: [`Snapshot::evaluate`] is the walk, [`Snapshot::answer`] adds the
//! normalization and the cache the Go engine used to own.

use super::Snapshot;
#[cfg(test)]
use crate::cache::DecisionCache;
use crate::cache::Reason;
use crate::text::{go_trim_space, normalize_domain};

/// One query's verdict plus an owned reason, so the FFI can hand Go a pointer that outlives the
/// cache entry that produced it.
pub struct Answer {
    pub blocked: bool,
    pub reason: Reason,
}

impl Answer {
    fn pass() -> Answer {
        Answer {
            blocked: false,
            reason: Reason::empty(),
        }
    }
}

impl Snapshot {
    #[cfg(test)]
    pub(crate) fn cache(&self) -> Option<&DecisionCache> {
        self.cache.as_ref()
    }

    /// The FFI entry point: normalizes the domain and the app name, answers from the decision cache
    /// and only walks the tables on a miss.
    pub fn answer(&self, domain: &str, app: &str, qtype: u16) -> Answer {
        let Some(cache) = &self.cache else {
            return Answer::pass();
        };
        let domain = normalize_domain(domain);
        if domain.is_empty() {
            return Answer::pass();
        }
        let app = go_trim_space(app);
        if let Some((blocked, reason)) = cache.get(&domain, app, qtype) {
            return Answer { blocked, reason };
        }
        let answer = self.verdict(&domain, app, qtype);
        cache.put(
            &domain,
            app,
            qtype,
            answer.blocked,
            answer.reason.clone(),
            1,
        );
        answer
    }

    /// Same verdict without touching the cache: prewarming builds entries with it, and the test
    /// suite uses it to prove a cache hit never changes an answer.
    pub fn answer_uncached(&self, domain: &str, app: &str, qtype: u16) -> Answer {
        if self.cache.is_none() {
            return Answer::pass();
        }
        let domain = normalize_domain(domain);
        if domain.is_empty() {
            return Answer::pass();
        }
        self.verdict(&domain, go_trim_space(app), qtype)
    }

    /// Re-evaluates the previous snapshot's hottest keys against this one, in the background of a
    /// rule reload. Keys are only carried over when both snapshots agree on which dimensions the
    /// cache key needs; hit counts are not carried over, so one reload cannot pin old hot keys.
    pub fn prewarm_from(&self, previous: &Snapshot) {
        if !self.filter_enabled || !self.has_rules {
            return;
        }
        let (Some(next), Some(previous_cache)) = (&self.cache, &previous.cache) else {
            return;
        };
        if self.app_sensitive != previous.app_sensitive
            || self.qtype_sensitive != previous.qtype_sensitive
        {
            return;
        }
        for key in previous_cache.hottest(crate::cache::PREWARM_TOP_N) {
            let answer = self.verdict(key.domain(), key.app(), key.qtype());
            next.put(
                key.domain(),
                key.app(),
                key.qtype(),
                answer.blocked,
                answer.reason,
                0,
            );
        }
    }

    /// The raw walk: no normalization, no cache. `evaluateNormalized` used to do exactly this.
    fn verdict(&self, domain: &str, app: &str, qtype: u16) -> Answer {
        let decision = self.evaluate(domain, app, qtype);
        debug_assert!(
            decision.reason.is_empty() || self.cache.is_some(),
            "a non-empty reason needs the cache's pool to stay alive"
        );
        let reason = match &self.cache {
            Some(cache) => cache.intern(decision.reason),
            None => Reason::empty(),
        };
        Answer {
            blocked: decision.blocked,
            reason,
        }
    }
}

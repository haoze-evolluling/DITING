//! The two checkers behind one handle: Safe Browsing and parental control.
//!
//! This is the state `SafeBrowsingEngine` held in Go: one cache per service, plus the "did the
//! configuration change?" comparison that rebuilds both caches. Everything around it (resolver
//! call, timeout, fail-open, counters, logging) needs Go callbacks and therefore stays in Go.

use std::sync::Mutex;

use crate::cache::HashCache;
use crate::hash::{build_question_name, hostname_to_hashes, normalize_check_host, HostnameHash};

/// Service id of the malicious-URL list.
pub const SERVICE_SAFE_BROWSING: u8 = 0;
/// Service id of parental control.
pub const SERVICE_PARENTAL_CONTROL: u8 = 1;

/// TXT suffix of the malicious-URL list queries.
pub const SAFE_BROWSING_SUFFIX: &str = "sb.dns.adguard.com.";
/// TXT suffix of the parental-control queries.
pub const PARENTAL_CONTROL_SUFFIX: &str = "pc.dns.adguard.com.";

/// What one service still needs, or already answered.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    /// The host has no digest at all (it is the public suffix itself): no verdict, no counters.
    pub empty: bool,
    /// Every prefix was cached; `blocked` is the answer.
    pub found: bool,
    /// One of the digests is listed. Only meaningful when `found`.
    pub blocked: bool,
    /// Digests to ask the third party for. Empty when `found`.
    pub need_query: Vec<HostnameHash>,
    /// Query name for `need_query`, built here so the prefix-hex layout has one owner.
    pub question: String,
}

struct State {
    safe_browsing: HashCache,
    parental_control: HashCache,
}

/// One reputation kernel: both services' caches behind a mutex.
pub struct Engine {
    state: Mutex<State>,
}

impl Engine {
    /// Builds both caches from the configured size and TTL (milliseconds).
    pub fn new(cache_size: i64, cache_ttl_ms: i64) -> Self {
        Self {
            state: Mutex::new(State {
                safe_browsing: HashCache::new(cache_size, cache_ttl_ms),
                parental_control: HashCache::new(cache_size, cache_ttl_ms),
            }),
        }
    }

    /// Applies a new size/TTL, rebuilding both caches when either changed.
    ///
    /// The comparison is against the *raw* configured size, like `Configure` did
    /// (`e.sb.cache.size != cfg.CacheSize`): a configuration that asks for 0 entries therefore
    /// rebuilds on every call, because the live cache holds the default 10000. That quirk is
    /// preserved rather than fixed — it only ever costs a cleared cache.
    pub fn configure(&self, cache_size: i64, cache_ttl_ms: i64) {
        let mut state = self.lock();
        let rebuild = state.safe_browsing.size as i64 != cache_size
            || state.safe_browsing.ttl_ms != cache_ttl_ms;
        if rebuild {
            state.safe_browsing = HashCache::new(cache_size, cache_ttl_ms);
            state.parental_control = HashCache::new(cache_size, cache_ttl_ms);
        }
    }

    /// Live entry count of one service's cache (`None` for an unknown service id).
    pub fn cache_entries(&self, service: u8) -> Option<usize> {
        let state = self.lock();
        let id = Service::from_id(service)?;
        Some(state.cache(id).len())
    }

    /// Normalizes `host` and reports what `service` still needs.
    ///
    /// `None` means "no verdict": the host is empty or not a domain name, so the caller passes the
    /// query through without touching the cache, the resolver or the counters.
    pub fn plan(&self, service: u8, host: &str, now_ms: i64) -> Option<Plan> {
        let id = Service::from_id(service)?;
        let host = normalize_check_host(host)?;
        let hashes = hostname_to_hashes(&host);

        let mut state = self.lock();
        let lookup = state.cache_mut(id).lookup(&hashes, now_ms);
        let question = build_question_name(&lookup.need_query, id.suffix());
        Some(Plan {
            empty: hashes.is_empty(),
            found: lookup.found,
            blocked: lookup.blocked,
            need_query: lookup.need_query,
            question,
        })
    }

    /// Stores the answer for `queried` and reports whether it blocks.
    ///
    /// `received` must already be the digest set (the caller parses the TXT chunks with
    /// [`crate::hash::parse_txt_hashes`]); `false` for an unknown service id.
    pub fn apply(
        &self,
        service: u8,
        queried: &[HostnameHash],
        received: &[HostnameHash],
        now_ms: i64,
    ) -> bool {
        let Some(id) = Service::from_id(service) else {
            return false;
        };
        let mut state = self.lock();
        state.cache_mut(id).store(queried, received, now_ms);
        queried.iter().any(|hash| received.contains(hash))
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        match self.state.lock() {
            Ok(guard) => guard,
            // A poisoned mutex means another call panicked mid-update; the caches are plain maps
            // and stay consistent, so recovering is safe and keeps the service answering.
            Err(poisoned) => poisoned.into_inner(),
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum Service {
    SafeBrowsing,
    ParentalControl,
}

impl Service {
    fn from_id(id: u8) -> Option<Self> {
        match id {
            SERVICE_SAFE_BROWSING => Some(Self::SafeBrowsing),
            SERVICE_PARENTAL_CONTROL => Some(Self::ParentalControl),
            _ => None,
        }
    }

    fn suffix(self) -> &'static str {
        match self {
            Self::SafeBrowsing => SAFE_BROWSING_SUFFIX,
            Self::ParentalControl => PARENTAL_CONTROL_SUFFIX,
        }
    }
}

impl State {
    fn cache(&self, service: Service) -> &HashCache {
        match service {
            Service::SafeBrowsing => &self.safe_browsing,
            Service::ParentalControl => &self.parental_control,
        }
    }

    fn cache_mut(&mut self, service: Service) -> &mut HashCache {
        match service {
            Service::SafeBrowsing => &mut self.safe_browsing,
            Service::ParentalControl => &mut self.parental_control,
        }
    }
}

#[cfg(test)]
mod tests;

use std::sync::Mutex;

use crate::cache::HashCache;
use crate::hash::{build_question_name, hostname_to_hashes, normalize_check_host, HostnameHash};

pub const SERVICE_SAFE_BROWSING: u8 = 0;
pub const SERVICE_PARENTAL_CONTROL: u8 = 1;

pub const SAFE_BROWSING_SUFFIX: &str = "sb.dns.adguard.com.";
pub const PARENTAL_CONTROL_SUFFIX: &str = "pc.dns.adguard.com.";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub empty: bool,
    pub found: bool,
    pub blocked: bool,
    pub need_query: Vec<HostnameHash>,
    pub question: String,
}

struct State {
    safe_browsing: HashCache,
    parental_control: HashCache,
}

pub struct Engine {
    state: Mutex<State>,
}

impl Engine {
    pub fn new(cache_size: i64, cache_ttl_ms: i64) -> Self {
        Self {
            state: Mutex::new(State {
                safe_browsing: HashCache::new(cache_size, cache_ttl_ms),
                parental_control: HashCache::new(cache_size, cache_ttl_ms),
            }),
        }
    }

    pub fn configure(&self, cache_size: i64, cache_ttl_ms: i64) {
        let mut state = self.lock();
        let rebuild = state.safe_browsing.size as i64 != cache_size
            || state.safe_browsing.ttl_ms != cache_ttl_ms;
        if rebuild {
            state.safe_browsing = HashCache::new(cache_size, cache_ttl_ms);
            state.parental_control = HashCache::new(cache_size, cache_ttl_ms);
        }
    }

    pub fn cache_entries(&self, service: u8) -> Option<usize> {
        let state = self.lock();
        let id = Service::from_id(service)?;
        Some(state.cache(id).len())
    }

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

use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

use diting_go_compat::text::{go_lower, go_trim_space};

use crate::pattern::match_host_pattern;
use crate::sensitive::{is_ip_address, is_sensitive_host};

pub const DEFAULT_BLACKLIST_TTL_MS: i64 = 7 * 24 * 60 * 60 * 1000;

pub const FAILURE_WINDOW_MS: i64 = 10 * 60 * 1000;

const FAILURE_THRESHOLD: u32 = 3;

const CERT_REJECTED_THRESHOLD: u32 = 2;

const CERT_REJECTED_MARKERS: &[&str] = &[
    "unknown certificate",
    "certificate unknown",
    "bad certificate",
];

struct Entry {
    expires_at_ms: i64,
    reason: String,
}

struct Failure {
    count: u32,
    last_seen_ms: i64,
}

#[derive(Default)]
struct State {
    allowed_uids: HashSet<i64>,
    bypass: Vec<String>,
    blacklist: HashMap<String, Entry>,
    failures: HashMap<String, Failure>,
    blacklist_path: Option<PathBuf>,
}

pub struct BlacklistReport {
    pub host: String,
    pub reason: String,
    pub ttl_ms: i64,
    pub write_error: Option<String>,
}

pub struct FailureReport {
    pub recorded: bool,
    pub blacklisted: bool,
    pub count: u32,
    pub threshold: u32,
    pub host: String,
    pub blacklist: Option<BlacklistReport>,
}

pub struct Filter {
    state: RwLock<State>,
}

impl Default for Filter {
    fn default() -> Self {
        Self::new()
    }
}

impl Filter {
    pub fn new() -> Self {
        Self {
            state: RwLock::new(State::default()),
        }
    }

    pub fn set_allowed_uids_csv(&self, csv: &str) -> usize {
        let mut uids = HashSet::new();
        for token in csv.split(',') {
            let mut uid: i64 = 0;
            for byte in token.trim().bytes() {
                if byte.is_ascii_digit() {
                    uid = uid.wrapping_mul(10).wrapping_add(i64::from(byte - b'0'));
                }
            }
            if uid > 0 {
                uids.insert(uid);
            }
        }
        let count = uids.len();
        self.state.write().unwrap().allowed_uids = uids;
        count
    }

    pub fn is_uid_allowed(&self, uid: i64) -> bool {
        self.state.read().unwrap().allowed_uids.contains(&uid)
    }

    pub fn has_allowed_uids(&self) -> bool {
        !self.state.read().unwrap().allowed_uids.is_empty()
    }

    pub fn set_bypass_rules(&self, content: &str) -> usize {
        let mut clean = Vec::new();
        for line in content.split('\n') {
            let rule = go_lower(go_trim_space(line));
            if rule.is_empty() || rule.starts_with('#') || rule.starts_with("//") {
                continue;
            }
            clean.push(rule.into_owned());
        }
        let count = clean.len();
        self.state.write().unwrap().bypass = clean;
        count
    }

    pub fn allows_interception(&self, host: &str, now_ms: i64) -> bool {
        let mut host = normalize(host);
        if let Some(index) = host.rfind(':') {
            host.truncate(index);
        }

        let expired = {
            let state = self.state.read().unwrap();
            match state.blacklist.get(&host) {
                Some(entry) if now_ms < entry.expires_at_ms => return false,
                Some(_) => true,
                None => false,
            }
        };
        if expired {
            let mut state = self.state.write().unwrap();
            if state
                .blacklist
                .get(&host)
                .is_some_and(|entry| now_ms >= entry.expires_at_ms)
            {
                state.blacklist.remove(&host);
            }
        }

        let bypassed = {
            let state = self.state.read().unwrap();
            state
                .bypass
                .iter()
                .any(|pattern| match_host_pattern(pattern, &host))
        };
        if bypassed {
            return false;
        }

        !is_sensitive_host(&host) && !is_ip_address(&host)
    }

    pub fn record_failure(&self, host: &str, error: &str, now_ms: i64) -> FailureReport {
        let host = normalize(host);
        if host.is_empty() {
            return FailureReport {
                recorded: false,
                blacklisted: false,
                count: 0,
                threshold: FAILURE_THRESHOLD,
                host,
                blacklist: None,
            };
        }

        let lowered = go_lower(error);
        let rejected = CERT_REJECTED_MARKERS
            .iter()
            .any(|marker| lowered.contains(marker));
        let (threshold, reason) = if rejected {
            (CERT_REJECTED_THRESHOLD, "cert_rejected")
        } else {
            (FAILURE_THRESHOLD, "handshake_failure")
        };

        let count = {
            let mut state = self.state.write().unwrap();
            match state.failures.get_mut(&host) {
                Some(record) if now_ms - record.last_seen_ms <= FAILURE_WINDOW_MS => {
                    record.count = record.count.saturating_add(1);
                    record.last_seen_ms = now_ms;
                    record.count
                }
                _ => {
                    state.failures.insert(
                        host.clone(),
                        Failure {
                            count: 1,
                            last_seen_ms: now_ms,
                        },
                    );
                    1
                }
            }
        };

        let (blacklist, blacklisted) = if count >= threshold {
            let reason = format!("{reason} ({count} failures)");
            match self.blacklist(&host, &reason, now_ms) {
                Some(added) => (Some(added), true),
                None => (None, self.is_blacklisted(&host, now_ms)),
            }
        } else {
            (None, false)
        };

        FailureReport {
            recorded: true,
            blacklisted,
            count,
            threshold,
            host,
            blacklist,
        }
    }

    pub fn is_blacklisted(&self, host: &str, now_ms: i64) -> bool {
        let host = normalize(host);
        let state = self.state.read().unwrap();
        state
            .blacklist
            .get(&host)
            .is_some_and(|entry| now_ms < entry.expires_at_ms)
    }

    pub fn blacklist(&self, host: &str, reason: &str, now_ms: i64) -> Option<BlacklistReport> {
        let host = normalize(host);
        if host.is_empty() {
            return None;
        }

        let mut state = self.state.write().unwrap();
        if let Some(entry) = state.blacklist.get(&host) {
            if now_ms < entry.expires_at_ms {
                return None;
            }
        }
        let expires_at_ms = now_ms.saturating_add(DEFAULT_BLACKLIST_TTL_MS);
        state.blacklist.insert(
            host.clone(),
            Entry {
                expires_at_ms,
                reason: reason.to_string(),
            },
        );
        let write_error = match state.blacklist_path.clone() {
            Some(path) => append_line(&path, &host, expires_at_ms, reason)
                .err()
                .map(|error| error.to_string()),
            None => None,
        };

        Some(BlacklistReport {
            host,
            reason: reason.to_string(),
            ttl_ms: DEFAULT_BLACKLIST_TTL_MS,
            write_error,
        })
    }

    pub fn clear_blacklist(&self) {
        let mut state = self.state.write().unwrap();
        state.blacklist.clear();
        state.failures.clear();
        if let Some(path) = state.blacklist_path.clone() {
            let _ = fs::write(&path, []);
        }
    }

    pub fn remove_from_blacklist(&self, host: &str) {
        let host = normalize(host);
        let mut state = self.state.write().unwrap();
        state.blacklist.remove(&host);
        state.failures.remove(&host);
    }

    pub fn load_persistent(&self, path: &str, now_ms: i64) -> usize {
        let mut loaded = 0;
        if let Ok(bytes) = fs::read(path) {
            let text = String::from_utf8_lossy(&bytes);
            let mut state = self.state.write().unwrap();
            for raw in text.split('\n') {
                let line = go_lower(go_trim_space(raw));
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                let parts: Vec<&str> = line.split('|').collect();
                let host = go_trim_space(parts[0]);
                if host.is_empty() {
                    continue;
                }
                let mut expires_at_ms = now_ms.saturating_add(DEFAULT_BLACKLIST_TTL_MS);
                let mut reason = String::from("pinning");
                if let Some(raw_expiry) = parts.get(1) {
                    if let Some(seconds) = parse_go_int(go_trim_space(raw_expiry)) {
                        let expiry = seconds.saturating_mul(1000);
                        if now_ms > expiry {
                            continue;
                        }
                        expires_at_ms = expiry;
                    }
                }
                if let Some(raw_reason) = parts.get(2) {
                    reason = go_trim_space(raw_reason).to_string();
                }
                state.blacklist.insert(
                    host.to_string(),
                    Entry {
                        expires_at_ms,
                        reason,
                    },
                );
                loaded += 1;
            }
        }

        self.state.write().unwrap().blacklist_path = Some(PathBuf::from(path));
        loaded
    }

    pub fn blacklist_count(&self, now_ms: i64) -> usize {
        let state = self.state.read().unwrap();
        state
            .blacklist
            .values()
            .filter(|entry| now_ms < entry.expires_at_ms)
            .count()
    }

    pub fn blacklist_reason(&self, host: &str, now_ms: i64) -> Option<String> {
        let host = normalize(host);
        let state = self.state.read().unwrap();
        state
            .blacklist
            .get(&host)
            .filter(|entry| now_ms < entry.expires_at_ms)
            .map(|entry| entry.reason.clone())
    }
}

fn normalize(host: &str) -> String {
    go_lower(go_trim_space(host)).into_owned()
}

fn parse_go_int(text: &str) -> Option<i64> {
    if text.is_empty() {
        return None;
    }
    text.parse::<i64>().ok()
}

fn append_line(path: &Path, host: &str, expires_at_ms: i64, reason: &str) -> std::io::Result<()> {
    let mut options = OpenOptions::new();
    options.append(true).create(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o644);
    }
    let mut file = options.open(path)?;
    let line = format!("{}|{}|{}\n", host, expires_at_ms.div_euclid(1000), reason);
    file.write_all(line.as_bytes())
}

#[cfg(test)]
mod tests;

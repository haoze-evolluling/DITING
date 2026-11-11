//! The filter state: per-UID allow list, bypass patterns, blacklist and failure streaks.
//!
//! Every method is a field-for-field port of `android/engine/mitm_filter.go`, including the order
//! of the checks in [`Filter::allows_interception`] (blacklist, then bypass patterns, then the
//! sensitive-host heuristics, then "is this even a hostname"), the Go `path.Match` patterns that
//! the exclusion rules are matched with, and the persistent blacklist file format
//! `host|unix_expiry|reason`.
//!
//! Time is injected as `now_ms` (unix milliseconds) on every stateful call: the kernel has no
//! clock, so expiry and the ten-minute failure window are pinned by the tests instead of being
//! read from the wall. The Go caller passes `time.Now().UnixMilli()`.
//!
//! Locking: one `RwLock` over the whole state. Decisions take the read lock; the blacklist path
//! (rare: a pinning failure or a completed failure streak) takes the write lock and *appends the
//! file line while holding it*, which serializes the appends without a second mutex.

use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::RwLock;

use diting_go_compat::text::{go_lower, go_trim_space};

use crate::pattern::match_host_pattern;
use crate::sensitive::{is_ip_address, is_sensitive_host};

/// `defaultBlacklistTTL`: how long an auto-blacklisted host stays out of the MITM path.
pub const DEFAULT_BLACKLIST_TTL_MS: i64 = 7 * 24 * 60 * 60 * 1000;

/// `10 * time.Minute`: how long a failure streak survives before it starts over.
pub const FAILURE_WINDOW_MS: i64 = 10 * 60 * 1000;

/// Failures needed before a host is blacklisted.
const FAILURE_THRESHOLD: u32 = 3;

/// Failures needed when the client rejected the minted certificate.
const CERT_REJECTED_THRESHOLD: u32 = 2;

/// Error texts that mean "the client refused our certificate": `threshold` drops to two.
const CERT_REJECTED_MARKERS: &[&str] = &[
    "unknown certificate",
    "certificate unknown",
    "bad certificate",
];

/// One blacklist entry.
struct Entry {
    expires_at_ms: i64,
    reason: String,
}

/// One failure streak.
struct Failure {
    count: u32,
    last_seen_ms: i64,
}

#[derive(Default)]
struct State {
    /// `allowedUIDs`: the apps whose flows may be intercepted.
    allowed_uids: HashSet<i64>,
    /// `httpsBypassPatterns`: normalized exclusion patterns.
    bypass: Vec<String>,
    blacklist: HashMap<String, Entry>,
    failures: HashMap<String, Failure>,
    /// `blacklistPath`: where new entries are appended and expires from at startup.
    blacklist_path: Option<PathBuf>,
}

/// What [`Filter::blacklist`] did.
pub struct BlacklistReport {
    /// The normalized host the entry was stored under.
    pub host: String,
    pub reason: String,
    pub ttl_ms: i64,
    /// Set when the entry could not be appended to the persistent file; the caller logs it.
    pub write_error: Option<String>,
}

/// What [`Filter::record_failure`] did, plus what the caller needs to log.
pub struct FailureReport {
    /// The failure streak was counted.
    pub recorded: bool,
    /// The host is blacklisted after the call, whether this call did it or not.
    pub blacklisted: bool,
    pub count: u32,
    pub threshold: u32,
    /// The normalized host the decision was made on.
    pub host: String,
    /// `Some` only when *this* call added the entry, i.e. when the caller logs it.
    pub blacklist: Option<BlacklistReport>,
}

/// The MITM filter.
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

    /// `SetAllowedUIDs`: the CSV is split on `,` and only the digit characters of each element are
    /// accumulated, exactly like the Go parser this replaced (`1a2` is UID 12, UID 0 is dropped).
    /// Returns how many UIDs are now allowed.
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

    /// `IsUIDAllowed`.
    pub fn is_uid_allowed(&self, uid: i64) -> bool {
        self.state.read().unwrap().allowed_uids.contains(&uid)
    }

    /// `HasAllowedUIDs`: false means "no app is being intercepted at all".
    pub fn has_allowed_uids(&self) -> bool {
        !self.state.read().unwrap().allowed_uids.is_empty()
    }

    /// `SetHttpsBypassRules`: one rule per line, lowered and trimmed, comments (`#`, `//`) and
    /// empty lines dropped. Returns how many rules were kept.
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

    /// `IsInterceptionAllowed`.
    pub fn allows_interception(&self, host: &str, now_ms: i64) -> bool {
        let mut host = normalize(host);
        // The Go original strips everything from the last colon, which also mangles IPv6 literals
        // — they still end up "not a hostname" below, so the outcome is unchanged.
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
            self.state.write().unwrap().blacklist.remove(&host);
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

    /// `RecordFailure`: counts a TLS failure for `host` and blacklists it once the streak reaches
    /// the threshold. The caller has already dropped a `nil` error, like the Go original.
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
                // Already known and still live: the host is blacklisted, but this call added
                // nothing and the Go caller has nothing new to log.
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

    /// Reports whether a live blacklist entry exists for `host` at `now_ms`.
    pub fn is_blacklisted(&self, host: &str, now_ms: i64) -> bool {
        let host = normalize(host);
        let state = self.state.read().unwrap();
        state
            .blacklist
            .get(&host)
            .is_some_and(|entry| now_ms < entry.expires_at_ms)
    }

    /// `BlacklistDomainWithReason`: keeps the host out of the MITM path for
    /// [`DEFAULT_BLACKLIST_TTL_MS`] and appends the line to the persistent file.
    ///
    /// `None` means "host is empty, or already known and not yet expired" — the Go original
    /// returned early there without touching the file.
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
        // Appends happen under the write lock: one mutex for the state and the file, no interleaved
        // partial lines.
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

    /// `ClearBlacklist`: drops every entry and every failure streak, then truncates the file.
    pub fn clear_blacklist(&self) {
        let mut state = self.state.write().unwrap();
        state.blacklist.clear();
        state.failures.clear();
        if let Some(path) = state.blacklist_path.clone() {
            // The Go original ignored this error (`_ = os.WriteFile`); an unreadable file only
            // means the old entries come back on the next start.
            let _ = fs::write(&path, []);
        }
    }

    /// `RemoveFromBlacklist`: forgets one host, file untouched (the Go original did the same).
    pub fn remove_from_blacklist(&self, host: &str) {
        let host = normalize(host);
        let mut state = self.state.write().unwrap();
        state.blacklist.remove(&host);
        state.failures.remove(&host);
    }

    /// `LoadPersistentBlacklist`: reads the file, keeps the entries that have not expired, and
    /// remembers the path for later appends. A missing file is not an error: it is the first run.
    ///
    /// Returns how many entries were loaded.
    pub fn load_persistent(&self, path: &str, now_ms: i64) -> usize {
        let mut loaded = 0;
        if let Ok(bytes) = fs::read(path) {
            let text = String::from_utf8_lossy(&bytes);
            let mut state = self.state.write().unwrap();
            for raw in text.split('\n') {
                // The Go scanner trimmed the line and then lowercased it, so the reason is
                // lowercased too.
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

    /// `GetBlacklistCount`: entries that are still live at `now_ms`.
    pub fn blacklist_count(&self, now_ms: i64) -> usize {
        let state = self.state.read().unwrap();
        state
            .blacklist
            .values()
            .filter(|entry| now_ms < entry.expires_at_ms)
            .count()
    }

    /// The reason recorded for a live entry. The Go side only asks for the count; this exists so
    /// the tests can prove the reason survived the persistent-file round trip (the entry keeps it
    /// because the file format carries it, exactly like the Go `blacklistEntry` did).
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

/// `strings.ToLower(strings.TrimSpace(host))`.
fn normalize(host: &str) -> String {
    go_lower(go_trim_space(host)).into_owned()
}

/// `strconv.ParseInt(s, 10, 64)`.
fn parse_go_int(text: &str) -> Option<i64> {
    if text.is_empty() {
        return None;
    }
    text.parse::<i64>().ok()
}

/// Appends `host|unix_seconds|reason` to the blacklist file, creating it if needed.
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

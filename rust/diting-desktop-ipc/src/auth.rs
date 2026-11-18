//! Administrator credentials, login throttling and sessions.
//!
//! Mirrors the former Go service's `internal/auth/auth.go`: SHA-256(salt ‖ password) hex digests, five
//! failures lock an address for five minutes and sessions expire after the configured timeout.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};

use diting_desktop_api::config::WebConfig;

pub const MAX_FAILED_ATTEMPTS: u32 = 5;
pub const LOCKOUT: Duration = Duration::from_secs(5 * 60);
pub const DEFAULT_SESSION_TTL: Duration = Duration::from_secs(7 * 24 * 3600);
const MAX_TRACKED_CLIENTS: usize = 4096;
/// Sessions kept at once. Expired ones are pruned on every login; this only bounds the case where
/// many logins happen inside one TTL window.
const MAX_SESSIONS: usize = 1024;

/// One issued session.
#[derive(Debug, Clone)]
pub struct SessionInfo {
    pub token: String,
    pub username: String,
    pub client_ip: String,
    pub created_at_unix: i64,
    pub expires_at_unix: i64,
}

struct Session {
    username: String,
    client_ip: String,
    expires: Instant,
    created_at_unix: i64,
    expires_at_unix: i64,
}

struct Attempt {
    count: u32,
    last_failure: Instant,
    locked_until: Option<Instant>,
}

struct State {
    username: String,
    password_hash: String,
    salt: String,
    session_timeout: Duration,
    attempts: HashMap<String, Attempt>,
    sessions: HashMap<String, Session>,
}

/// Thread-safe credential/session manager.
pub struct AuthManager {
    state: Mutex<State>,
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

fn random_hex(len: usize) -> String {
    let mut bytes = vec![0u8; len];
    rand::fill(&mut bytes[..]);
    hex_encode(&bytes)
}

/// Salted SHA-256 password hash. `salt` is generated when empty.
pub fn hash_password(password: &str, salt: &str) -> (String, String) {
    let used_salt = if salt.is_empty() {
        random_hex(16)
    } else {
        salt.to_string()
    };
    let mut hasher = Sha256::new();
    hasher.update(used_salt.as_bytes());
    hasher.update(password.as_bytes());
    (hex_encode(&hasher.finalize()), used_salt)
}

fn constant_time_eq(left: &str, right: &str) -> bool {
    let left = left.as_bytes();
    let right = right.as_bytes();
    if left.len() != right.len() {
        return false;
    }
    let mut difference = 0u8;
    for (a, b) in left.iter().zip(right.iter()) {
        difference |= a ^ b;
    }
    difference == 0
}

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

impl AuthManager {
    /// Builds the manager from the persisted `web` configuration block.
    pub fn from_web(config: &WebConfig) -> Self {
        let nanos = config.session_timeout.0.max(0) as u64;
        let session_timeout = if nanos == 0 {
            DEFAULT_SESSION_TTL
        } else {
            Duration::from_nanos(nanos)
        };
        let username = if config.username.trim().is_empty() {
            "admin".to_string()
        } else {
            config.username.trim().to_string()
        };
        Self {
            state: Mutex::new(State {
                username,
                password_hash: config.password_hash.clone(),
                salt: config.salt.clone(),
                session_timeout,
                attempts: HashMap::new(),
                sessions: HashMap::new(),
            }),
        }
    }

    /// Test-friendly constructor.
    pub fn new(username: &str, password_hash: &str, salt: &str, session_timeout: Duration) -> Self {
        Self {
            state: Mutex::new(State {
                username: if username.is_empty() {
                    "admin".to_string()
                } else {
                    username.to_string()
                },
                password_hash: password_hash.to_string(),
                salt: salt.to_string(),
                session_timeout: if session_timeout.is_zero() {
                    DEFAULT_SESSION_TTL
                } else {
                    session_timeout
                },
                attempts: HashMap::new(),
                sessions: HashMap::new(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }

    pub fn is_initialized(&self) -> bool {
        !self.lock().password_hash.is_empty()
    }

    pub fn username(&self) -> String {
        self.lock().username.clone()
    }

    pub fn credentials(&self) -> (String, String, String) {
        let state = self.lock();
        (
            state.username.clone(),
            state.password_hash.clone(),
            state.salt.clone(),
        )
    }

    fn prune(state: &mut State, now: Instant) {
        state
            .attempts
            .retain(|_, attempt| match attempt.locked_until {
                Some(until) => now < until,
                None => now.duration_since(attempt.last_failure) <= LOCKOUT,
            });
        if state.attempts.len() > MAX_TRACKED_CLIENTS {
            let excess = state.attempts.len() - MAX_TRACKED_CLIENTS;
            let mut oldest: Vec<(String, Instant)> = state
                .attempts
                .iter()
                .filter(|(_, attempt)| attempt.locked_until.is_none())
                .map(|(ip, attempt)| (ip.clone(), attempt.last_failure))
                .collect();
            oldest.sort_by_key(|(_, at)| *at);
            for (ip, _) in oldest.into_iter().take(excess) {
                state.attempts.remove(&ip);
            }
        }

        // Sessions were only ever dropped when presented again, so expired tokens accumulated for
        // as long as nobody used them.
        state.sessions.retain(|_, session| now < session.expires);
        if state.sessions.len() > MAX_SESSIONS {
            let excess = state.sessions.len() - MAX_SESSIONS;
            let mut oldest: Vec<(String, i64)> = state
                .sessions
                .iter()
                .map(|(token, session)| (token.clone(), session.created_at_unix))
                .collect();
            oldest.sort_by_key(|(_, created)| *created);
            for (token, _) in oldest.into_iter().take(excess) {
                state.sessions.remove(&token);
            }
        }
    }

    fn record_failure(state: &mut State, client_ip: &str, now: Instant) -> String {
        let attempt = state
            .attempts
            .entry(client_ip.to_string())
            .or_insert(Attempt {
                count: 0,
                last_failure: now,
                locked_until: None,
            });
        attempt.count += 1;
        attempt.last_failure = now;
        if attempt.count >= MAX_FAILED_ATTEMPTS {
            attempt.locked_until = Some(now + LOCKOUT);
            attempt.count = 0;
            return format!("密码连续错误 {MAX_FAILED_ATTEMPTS} 次，已临时锁定 5 分钟");
        }
        let remaining = MAX_FAILED_ATTEMPTS - attempt.count;
        format!("用户名或密码错误 (剩余重试次数: {remaining})")
    }

    /// `CheckIPLockout` for status responses.
    pub fn lockout(&self, client_ip: &str) -> (bool, i64) {
        let state = self.lock();
        if let Some(attempt) = state.attempts.get(client_ip) {
            if let Some(until) = attempt.locked_until {
                let now = Instant::now();
                if now < until {
                    return (true, until.duration_since(now).as_secs() as i64);
                }
            }
        }
        (false, 0)
    }

    /// Validates a session token and drops it when expired.
    pub fn validate_session(&self, token: &str) -> Option<SessionInfo> {
        if token.is_empty() {
            return None;
        }
        let mut state = self.lock();
        let now = Instant::now();
        let session = state.sessions.get(token)?;
        if now >= session.expires {
            state.sessions.remove(token);
            return None;
        }
        Some(SessionInfo {
            token: token.to_string(),
            username: session.username.clone(),
            client_ip: session.client_ip.clone(),
            created_at_unix: session.created_at_unix,
            expires_at_unix: session.expires_at_unix,
        })
    }

    pub fn revoke_session(&self, token: &str) {
        if !token.is_empty() {
            self.lock().sessions.remove(token);
        }
    }

    /// `Login`.
    pub fn login(
        &self,
        username: &str,
        password: &str,
        client_ip: &str,
    ) -> Result<SessionInfo, String> {
        let mut state = self.lock();
        let now = Instant::now();
        Self::prune(&mut state, now);

        if let Some(attempt) = state.attempts.get(client_ip) {
            if let Some(until) = attempt.locked_until {
                if now < until {
                    let remaining = until.duration_since(now).as_secs();
                    return Err(format!(
                        "密码错误次数过多，账号已临时锁定，请在 {remaining} 秒后重试"
                    ));
                }
            }
        }

        if state.password_hash.is_empty() {
            return Err("管理员账号尚未初始化".to_string());
        }

        let (calculated, _) = hash_password(password, &state.salt);
        let user_match = constant_time_eq(username, &state.username);
        let pass_match = constant_time_eq(&calculated, &state.password_hash);
        if !user_match || !pass_match {
            return Err(Self::record_failure(&mut state, client_ip, now));
        }

        state.attempts.remove(client_ip);
        let token = random_hex(32);
        let created_at_unix = now_unix();
        let session_timeout = state.session_timeout;
        let username = state.username.clone();
        let expires_at_unix = created_at_unix + session_timeout.as_secs() as i64;
        let info = SessionInfo {
            token: token.clone(),
            username: username.clone(),
            client_ip: client_ip.to_string(),
            created_at_unix,
            expires_at_unix,
        };
        state.sessions.insert(
            token,
            Session {
                username,
                client_ip: client_ip.to_string(),
                expires: now + session_timeout,
                created_at_unix,
                expires_at_unix,
            },
        );
        Ok(info)
    }

    /// `VerifyPassword`.
    pub fn verify_password(&self, password: &str) -> bool {
        let state = self.lock();
        if state.password_hash.is_empty() {
            return false;
        }
        let (calculated, _) = hash_password(password, &state.salt);
        constant_time_eq(&calculated, &state.password_hash)
    }

    /// `VerifyPasswordWithIP`: same throttle table as login.
    pub fn verify_password_with_ip(&self, client_ip: &str, password: &str) -> Result<bool, String> {
        let mut state = self.lock();
        let now = Instant::now();
        Self::prune(&mut state, now);
        if let Some(attempt) = state.attempts.get(client_ip) {
            if let Some(until) = attempt.locked_until {
                if now < until {
                    let remaining = until.duration_since(now).as_secs();
                    return Err(format!(
                        "密码错误次数过多，账号已临时锁定，请在 {remaining} 秒后重试"
                    ));
                }
            }
        }
        if state.password_hash.is_empty() {
            return Err("管理员账号尚未初始化".to_string());
        }
        let (calculated, _) = hash_password(password, &state.salt);
        if !constant_time_eq(&calculated, &state.password_hash) {
            return Err(Self::record_failure(&mut state, client_ip, now));
        }
        state.attempts.remove(client_ip);
        Ok(true)
    }

    /// `SetupInitialCredentials`.
    pub fn setup(
        &self,
        username: &str,
        password: &str,
    ) -> Result<(String, String, String), String> {
        if password.chars().count() < 4 {
            return Err("密码长度不能少于 4 位字符".to_string());
        }
        let mut state = self.lock();
        if !state.password_hash.is_empty() {
            return Err("管理员账号已初始化，请使用修改密码功能".to_string());
        }
        let username = if username.trim().is_empty() {
            "admin".to_string()
        } else {
            username.trim().to_string()
        };
        let (hash, salt) = hash_password(password, "");
        state.username = username.clone();
        state.password_hash = hash.clone();
        state.salt = salt.clone();
        Ok((username, hash, salt))
    }

    /// `UpdateCredentials`; `bypass_old` is set for trusted local IPC callers.
    pub fn update_credentials(
        &self,
        username: &str,
        old_password: &str,
        new_password: &str,
        bypass_old: bool,
    ) -> Result<(String, String, String), String> {
        if new_password.chars().count() < 4 {
            return Err("新密码长度不能少于 4 位字符".to_string());
        }
        let mut state = self.lock();
        if !bypass_old && !state.password_hash.is_empty() {
            let (calculated, _) = hash_password(old_password, &state.salt);
            if !constant_time_eq(&calculated, &state.password_hash) {
                return Err("原密码不正确".to_string());
            }
        }
        let username = if username.trim().is_empty() {
            if state.username.is_empty() {
                "admin".to_string()
            } else {
                state.username.clone()
            }
        } else {
            username.trim().to_string()
        };
        let (hash, salt) = hash_password(new_password, "");
        state.username = username.clone();
        state.password_hash = hash.clone();
        state.salt = salt.clone();
        state.sessions.clear();
        Ok((username, hash, salt))
    }

    /// Updates stored credentials from a config reload (no validation).
    pub fn reload(&self, username: &str, hash: &str, salt: &str, timeout: Duration) {
        let mut state = self.lock();
        state.username = if username.is_empty() {
            "admin".to_string()
        } else {
            username.to_string()
        };
        state.password_hash = hash.to_string();
        state.salt = salt.to_string();
        if !timeout.is_zero() {
            state.session_timeout = timeout;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manager() -> AuthManager {
        let (hash, salt) = hash_password("secret", "");
        AuthManager::new("admin", &hash, &salt, Duration::from_secs(60))
    }

    #[test]
    fn password_hash_is_salted_and_stable() {
        let (first, salt) = hash_password("secret", "");
        let (second, _) = hash_password("secret", &salt);
        assert_eq!(first, second);
        let (_other, other_salt) = hash_password("secret", "");
        assert_ne!(salt, other_salt);
        assert_ne!(first, "secret");
    }

    #[test]
    fn five_failures_lock_the_address() {
        let auth = manager();
        for _ in 0..MAX_FAILED_ATTEMPTS - 1 {
            assert!(auth.login("admin", "wrong", "10.0.0.1").is_err());
        }
        let error = auth.login("admin", "wrong", "10.0.0.1").unwrap_err();
        assert!(error.contains("锁定"));
        assert!(auth.lockout("10.0.0.1").0);
        // A correct password is still refused while locked.
        assert!(auth.login("admin", "secret", "10.0.0.1").is_err());
        // Another address is unaffected.
        assert!(auth.login("admin", "secret", "10.0.0.2").is_ok());
    }

    #[test]
    fn login_issues_and_revokes_sessions() {
        let auth = manager();
        let session = auth.login("admin", "secret", "127.0.0.1").unwrap();
        assert_eq!(session.username, "admin");
        assert!(auth.validate_session(&session.token).is_some());
        auth.revoke_session(&session.token);
        assert!(auth.validate_session(&session.token).is_none());
    }

    #[test]
    fn expired_sessions_are_rejected() {
        let auth = AuthManager::new("admin", "hash", "salt", Duration::from_millis(1));
        let (hash, salt) = hash_password("secret", "");
        auth.reload("admin", &hash, &salt, Duration::from_millis(1));
        let session = auth.login("admin", "secret", "127.0.0.1").unwrap();
        std::thread::sleep(Duration::from_millis(5));
        assert!(auth.validate_session(&session.token).is_none());
    }

    #[test]
    fn setup_only_once_and_password_length_enforced() {
        let auth = AuthManager::new("admin", "", "", Duration::from_secs(60));
        assert!(auth.setup("admin", "abc").is_err());
        assert!(auth.setup("admin", "abcd").is_ok());
        assert!(auth.setup("admin", "abcde").is_err());
        assert!(auth.verify_password("abcd"));
    }
}

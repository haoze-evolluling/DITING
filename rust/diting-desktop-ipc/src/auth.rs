use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};

use diting_desktop_api::config::WebConfig;

use crate::session::SessionStore;

pub const MAX_FAILED_ATTEMPTS: u32 = 5;
pub const LOCKOUT: Duration = Duration::from_secs(5 * 60);
pub const DEFAULT_SESSION_TTL: Duration = Duration::from_secs(7 * 24 * 3600);
const MAX_TRACKED_CLIENTS: usize = 4096;
const MAX_SESSIONS: usize = 1024;

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

pub struct AuthManager {
    state: Mutex<State>,
    store: Option<Arc<dyn SessionStore>>,
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
    pub fn from_web(config: &WebConfig) -> Self {
        Self::from_web_with_store(config, None)
    }

    pub fn from_web_with_store(config: &WebConfig, store: Option<Arc<dyn SessionStore>>) -> Self {
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
        let manager = Self {
            state: Mutex::new(State {
                username,
                password_hash: config.password_hash.clone(),
                salt: config.salt.clone(),
                session_timeout,
                attempts: HashMap::new(),
                sessions: HashMap::new(),
            }),
            store: store.clone(),
        };
        manager.hydrate_sessions();
        manager
    }

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
            store: None,
        }
    }

    fn hydrate_sessions(&self) {
        let Some(store) = self.store.clone() else {
            return;
        };
        let now_unix = now_unix();
        store.prune(now_unix);
        let now = Instant::now();
        let mut state = self.lock();
        for info in store.load() {
            let remaining = info.expires_at_unix.saturating_sub(now_unix);
            if remaining <= 0 {
                continue;
            }
            state.sessions.insert(
                info.token,
                Session {
                    username: info.username,
                    client_ip: info.client_ip,
                    expires: now + Duration::from_secs(remaining as u64),
                    created_at_unix: info.created_at_unix,
                    expires_at_unix: info.expires_at_unix,
                },
            );
        }
        Self::prune(&mut state, now);
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

    /// 鉴权路径只需要一个布尔，不必为此克隆 `SessionInfo` 的 3 个 `String`。
    pub fn is_authenticated(&self, token: &str) -> bool {
        if token.is_empty() {
            return false;
        }
        let mut state = self.lock();
        let now = Instant::now();
        match state.sessions.get(token) {
            Some(session) if now < session.expires => true,
            Some(_) => {
                state.sessions.remove(token);
                false
            }
            None => false,
        }
    }

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
            if let Some(store) = &self.store {
                store.remove(token);
            }
        }
    }

    pub fn login(
        &self,
        username: &str,
        password: &str,
        client_ip: &str,
    ) -> Result<SessionInfo, String> {
        if let Some(store) = &self.store {
            store.prune(now_unix());
        }
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
        let store = self.store.clone();
        drop(state);
        if let Some(store) = store {
            store.insert(&info);
        }
        Ok(info)
    }

    pub fn verify_password(&self, password: &str) -> bool {
        let state = self.lock();
        if state.password_hash.is_empty() {
            return false;
        }
        let (calculated, _) = hash_password(password, &state.salt);
        constant_time_eq(&calculated, &state.password_hash)
    }

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
        let store = self.store.clone();
        drop(state);
        if let Some(store) = store {
            store.clear();
        }
        Ok((username, hash, salt))
    }

    /// 仅用于本机管理页的“忘记密码”：无需旧密码即可替换凭据，
    /// 同时清空会话与失败计数，避免重置后仍被临时锁定。
    pub fn reset_password(&self, new_password: &str) -> Result<(String, String, String), String> {
        if new_password.chars().count() < 4 {
            return Err("新密码长度不能少于 4 位字符".to_string());
        }
        let mut state = self.lock();
        if state.password_hash.is_empty() {
            return Err("管理员账号尚未初始化，请先创建管理员账户".to_string());
        }
        let username = state.username.clone();
        let (hash, salt) = hash_password(new_password, "");
        state.password_hash = hash.clone();
        state.salt = salt.clone();
        state.sessions.clear();
        state.attempts.clear();
        let store = self.store.clone();
        drop(state);
        if let Some(store) = store {
            store.clear();
        }
        Ok((username, hash, salt))
    }

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
        assert!(auth.login("admin", "secret", "10.0.0.1").is_err());
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

    #[test]
    fn reset_password_replaces_credentials_and_revokes_sessions() {
        let auth = manager();
        let session = auth.login("admin", "secret", "127.0.0.1").unwrap();
        assert!(auth.reset_password("abc").is_err());
        let (username, _, _) = auth.reset_password("new-secret").unwrap();
        assert_eq!(username, "admin");
        assert!(auth.validate_session(&session.token).is_none());
        assert!(auth.login("admin", "secret", "127.0.0.1").is_err());
        assert!(auth.login("admin", "new-secret", "127.0.0.1").is_ok());
    }
}

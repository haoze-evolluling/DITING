//! Cached QUIC session selection, shared by the DoH3 and DoQ transports.
//!
//! Both transports keep a `Mutex<HashMap<String, quinn::Connection>>` and have to answer the same
//! question: "is the cached session still usable, or should it be dropped and re-dialed?" The
//! lookup, the liveness check and the eviction must happen under **one** lock — see
//! [`take_live_session`] for the deadlock that splitting them causes.

use std::collections::HashMap;

/// Returns the live cached session for `key`, evicting it when `is_closed` says it is dead.
///
/// The caller already holds the map's guard and hands its `&mut` view in, so every step runs
/// under that one guard.
///
/// Do **not** inline this back into an `if let` over a mutex guard:
///
/// ```ignore
/// if let Some(connection) = self.lock_sessions().get(key).cloned() {
///     if connection.close_reason().is_some() {
///         self.lock_sessions().remove(key); // deadlock: the guard is still held
///     }
/// }
/// ```
///
/// The scrutinee's `MutexGuard` lives until the end of the `if let` body (temporary lifetime
/// extension), and `std::sync::Mutex` is not reentrant. The second lock would block the calling
/// task forever; because it blocks synchronously it never reaches its `tokio::time::timeout`, so
/// two such queries are enough to wedge every worker thread of the engine runtime.
pub(crate) fn take_live_session<T, F>(
    sessions: &mut HashMap<String, T>,
    key: &str,
    is_closed: F,
) -> Option<T>
where
    T: Clone,
    F: FnOnce(&T) -> bool,
{
    let session = sessions.get(key).cloned()?;
    if !is_closed(&session) {
        return Some(session);
    }
    sessions.remove(key);
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// `false` is a live session, `true` a closed one.
    fn sessions() -> HashMap<String, bool> {
        HashMap::from([
            ("live:443".to_string(), false),
            ("closed:443".to_string(), true),
        ])
    }

    #[test]
    fn a_live_session_is_returned_and_kept() {
        let mut sessions = sessions();
        assert_eq!(
            take_live_session(&mut sessions, "live:443", |closed| *closed),
            Some(false)
        );
        assert!(sessions.contains_key("live:443"));
    }

    #[test]
    fn a_closed_session_is_evicted() {
        let mut sessions = sessions();
        assert_eq!(
            take_live_session(&mut sessions, "closed:443", |closed| *closed),
            None
        );
        assert!(!sessions.contains_key("closed:443"));
    }

    #[test]
    fn an_unknown_key_is_none() {
        let mut sessions = sessions();
        assert_eq!(
            take_live_session(&mut sessions, "other:443", |closed| *closed),
            None
        );
    }

    /// The guard created at the call site must be released when the helper returns; a second
    /// `try_lock` is what proves the helper itself never splits the lock.
    #[test]
    fn the_lock_is_released_when_the_helper_returns() {
        let sessions = Mutex::new(sessions());
        let found = take_live_session(&mut sessions.lock().unwrap(), "closed:443", |closed| {
            *closed
        });
        assert!(found.is_none());
        assert!(
            sessions.try_lock().is_ok(),
            "the caller's guard must be released"
        );
    }
}

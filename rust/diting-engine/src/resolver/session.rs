use std::collections::HashMap;

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

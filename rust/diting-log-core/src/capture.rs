use std::sync::Mutex;

use crate::store::MAX_FILE_BYTES;

pub const WATCH_INTERVAL_MS: i64 = 1_000;

pub type Attempt = Vec<String>;

fn argv(parts: &[&str]) -> Vec<String> {
    parts.iter().map(|part| (*part).to_string()).collect()
}

pub fn attempts(pid: i32, uid: i32, detailed: bool) -> Vec<Attempt> {
    if detailed {
        return vec![argv(&["logcat", "-v", "time", "-b", "all"])];
    }
    let mut out: Vec<Attempt> = Vec::with_capacity(3);
    if uid > 0 {
        out.push(vec![
            "logcat".to_string(),
            "-v".to_string(),
            "time".to_string(),
            "--uid".to_string(),
            uid.to_string(),
        ]);
    } else if pid > 0 {
        out.push(vec![
            "logcat".to_string(),
            "-v".to_string(),
            "time".to_string(),
            "--pid".to_string(),
            pid.to_string(),
        ]);
    }
    out.push(argv(&["logcat", "-v", "time"]));
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LineCost {
    pub written: i64,
    pub rotate: bool,
}

#[derive(Debug, Default)]
struct Budget {
    written: i64,
}

#[derive(Debug)]
pub struct Session {
    budget: Mutex<Budget>,
}

impl Default for Session {
    fn default() -> Self {
        Self::new()
    }
}

impl Session {
    pub fn new() -> Self {
        Self {
            budget: Mutex::new(Budget::default()),
        }
    }

    pub fn on_line(&self, line: &str) -> LineCost {
        let cost = line.encode_utf16().count() as i64 + 1;
        let mut budget = self
            .budget
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        budget.written = budget.written.saturating_add(cost);
        LineCost {
            written: budget.written,
            rotate: budget.written >= MAX_FILE_BYTES,
        }
    }

    pub fn written(&self) -> i64 {
        self.budget
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .written
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(parts: &[&str]) -> Vec<String> {
        parts.iter().map(|part| (*part).to_string()).collect()
    }

    #[test]
    fn the_uid_filter_comes_first_then_the_unfiltered_fallback() {
        let attempts = attempts(4242, 10123, false);
        assert_eq!(attempts.len(), 2);
        assert_eq!(
            attempts[0],
            args(&["logcat", "-v", "time", "--uid", "10123"])
        );
        assert_eq!(attempts[1], args(&["logcat", "-v", "time"]));
    }

    #[test]
    fn an_unknown_uid_falls_back_to_the_pid_and_then_unfiltered() {
        let got = attempts(4242, 0, false);
        assert_eq!(got.len(), 2);
        assert_eq!(got[0], args(&["logcat", "-v", "time", "--pid", "4242"]));
        assert_eq!(got[1], args(&["logcat", "-v", "time"]));

        let none = attempts(0, -1, false);
        assert_eq!(none.len(), 1);
        assert_eq!(none[0], args(&["logcat", "-v", "time"]));
    }

    #[test]
    fn detailed_mode_is_a_single_all_buffer_reader() {
        let attempts = attempts(4242, 10123, true);
        assert_eq!(attempts.len(), 1);
        assert_eq!(attempts[0], args(&["logcat", "-v", "time", "-b", "all"]));
    }

    #[test]
    fn every_line_costs_its_length_plus_the_newline() {
        let session = Session::new();
        assert_eq!(
            session.on_line("hello"),
            LineCost {
                written: 6,
                rotate: false
            }
        );
        assert_eq!(
            session.on_line(""),
            LineCost {
                written: 7,
                rotate: false
            }
        );
        assert_eq!(
            session.on_line("🌐"),
            LineCost {
                written: 10,
                rotate: false
            }
        );
        assert_eq!(session.written(), 10);
    }

    #[test]
    fn the_file_rotates_once_the_budget_is_reached() {
        let session = Session::new();
        let chunk = "x".repeat(1_000_000);
        assert!(!session.on_line(&chunk).rotate);
        assert!(!session.on_line(&chunk).rotate);
        let rest = "y".repeat(97_148);
        let cost = session.on_line(&rest);
        assert_eq!(cost.written, MAX_FILE_BYTES - 1);
        assert!(!cost.rotate);
        let cost = session.on_line("last");
        assert_eq!(cost.written, MAX_FILE_BYTES + 4);
        assert!(cost.rotate);
    }
}

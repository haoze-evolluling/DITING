//! `RuntimeLogService`'s pure half: the `logcat` command attempts, the watchdog cadence and the
//! per-file byte budget that decides when a capture rotates.
//!
//! The service, its `Thread`s, the `Process` and `/proc/<pid>` checks stay in Kotlin. What moves
//! here is "which command, in which order" and "how much has this file held", so a rotation cannot
//! disagree with `MAX_FILE_BYTES`.

use std::sync::Mutex;

use crate::store::MAX_FILE_BYTES;

/// How often the watchdog checks whether the followed process still exists.
pub const WATCH_INTERVAL_MS: i64 = 1_000;

/// `--pid` keeps the capture to this app: less noise for the developer and a lower cost for the
/// user, which is what the confirmation dialog promises.
pub fn commands(pid: i32) -> Vec<Vec<String>> {
    let mut attempts: Vec<Vec<String>> = Vec::with_capacity(2);
    if pid > 0 {
        attempts.push(
            ["logcat", "-v", "time", "--pid", &pid.to_string()]
                .iter()
                .map(|part| (*part).to_string())
                .collect(),
        );
    }
    // The unfiltered fallback: some devices refuse `--pid`, and a noisy capture beats none.
    attempts.push(
        ["logcat", "-v", "time"]
            .iter()
            .map(|part| (*part).to_string())
            .collect(),
    );
    attempts
}

/// What one appended line did to the budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LineCost {
    /// Characters written so far, including this line's newline.
    pub written: i64,
    /// The file reached [`MAX_FILE_BYTES`]; the loop starts a new one.
    pub rotate: bool,
}

#[derive(Debug, Default)]
struct Budget {
    written: i64,
}

/// One capture file's byte budget.
///
/// The counter is Kotlin's `String.length` (UTF-16 code units) plus the newline, which is what the
/// old loop added even though the constant says "bytes"; logcat output is ASCII, so the two only
/// differ for a non-BMP line, and matching the old numbers is worth more than a rename.
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

    /// Counts `line` into the current file and reports whether it is full now.
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

    #[test]
    fn the_pid_filter_comes_first_with_an_unfiltered_fallback() {
        assert_eq!(
            commands(4242),
            vec![
                vec!["logcat", "-v", "time", "--pid", "4242"],
                vec!["logcat", "-v", "time"],
            ]
            .into_iter()
            .map(|attempt| attempt.into_iter().map(str::to_string).collect::<Vec<_>>())
            .collect::<Vec<_>>()
        );
        // Without a pid there is nothing to filter on.
        assert_eq!(
            commands(0),
            vec![vec!["logcat", "-v", "time"]]
                .into_iter()
                .map(|attempt| attempt.into_iter().map(str::to_string).collect::<Vec<_>>())
                .collect::<Vec<_>>()
        );
        assert_eq!(commands(-1).len(), 1);
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
        // A non-BMP character is two UTF-16 units, exactly like `String.length`.
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
        // 1_000_001 + 1_000_001 = 2_000_002, still under the 2 MiB cap.
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

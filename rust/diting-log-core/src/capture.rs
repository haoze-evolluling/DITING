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

/// One `logcat` attempt: the argv the service runs, in order, until one starts.
pub type Attempt = Vec<String>;

fn argv(parts: &[&str]) -> Vec<String> {
    parts.iter().map(|part| (*part).to_string()).collect()
}

/// The `logcat` attempts for one capture, most useful first.
///
/// * `--uid <uid>` - every process the app owns, and (because `--uid` filters every default
///   buffer) the app's own `main`/`system`/`crash` lines. This is what replaces `--pid`: a
///   `--pid` reader can never see the system-side `am_anr` / `am_kill` / `am_proc_died` lines,
///   which is exactly where a silent "service stopped" shows up.
/// * `--pid <pid>` - the fallback for devices that reject `--uid`.
/// * unfiltered `logcat` - the last resort; a noisy capture beats none.
/// * detailed mode - one `-b all` reader for deep debugging (every buffer, every process).
///
/// The crash and `events` buffers are also read once at export by
/// `RuntimeLogStore.read`, filtered to this package, so another app's tombstone never reaches
/// this app's file and a crash that happened before capture started is still visible.
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

        // No pid and no uid: only the unfiltered reader is left.
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

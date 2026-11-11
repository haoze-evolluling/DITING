//! `DbWriteHealth`: the drop counters and the one-line-per-window warning gate.
//!
//! The counters exist because a silent "no logs at all" has to become visible, and the window
//! exists because 2.1.7 printed a 25-line stack trace per failed open from every callback thread.
//! Both are pure bookkeeping, so they live here; the `Log.w` call, the throwable and the
//! diagnostics-channel map shape stay in Kotlin.

use std::sync::Mutex;

/// One warning line per window; everything inside it is counted as suppressed.
pub const WARN_WINDOW_MS: i64 = 60_000;

/// Why rows were thrown away (`DbWriteHealth.DropReason`), in the enum's Kotlin order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DropReason {
    /// The bounded queue was full because the database stayed busy for too long.
    Overflow,
    /// The table really is not in the file (wrong database, or schema not created yet).
    TableMissing,
    /// No database file at all.
    NoDatabase,
    /// The writer was closed with rows it could no longer write.
    Closed,
}

impl DropReason {
    pub const ALL: [Self; 4] = [
        Self::Overflow,
        Self::TableMissing,
        Self::NoDatabase,
        Self::Closed,
    ];

    /// Payload tag; an unknown tag is drift.
    pub fn from_tag(tag: u8) -> Option<Self> {
        Self::ALL.get(tag as usize).copied()
    }

    pub fn tag(self) -> u8 {
        Self::ALL.iter().position(|reason| *reason == self).unwrap() as u8
    }

    /// `DropReason.key`, the spelling the diagnostics channel exposes.
    pub fn key(self) -> &'static str {
        match self {
            Self::Overflow => "overflow",
            Self::TableMissing => "tableMissing",
            Self::NoDatabase => "noDatabase",
            Self::Closed => "closed",
        }
    }
}

/// `DbWriteHealth.snapshot()`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HealthSnapshot {
    pub dropped_rows: i64,
    /// In [`DropReason::ALL`] order.
    pub dropped_by_reason: [i64; 4],
    pub last_drop: String,
    pub open_failures: i64,
    pub suppressed: i64,
    pub last_cause: String,
}

#[derive(Debug, Default)]
struct Inner {
    dropped_rows: i64,
    dropped_by_reason: [i64; 4],
    last_drop: Option<String>,
    open_failures: i64,
    suppressed: i64,
    last_warn_at: i64,
    last_cause: Option<String>,
}

/// The counters and the warning window.
#[derive(Debug, Default)]
pub struct Health {
    inner: Mutex<Inner>,
}

impl Health {
    pub fn new() -> Self {
        Self::default()
    }

    /// `onDropped`: count the rows, then let the window decide whether to say anything.
    pub fn on_dropped(
        &self,
        rows: i32,
        reason: DropReason,
        table: &str,
        now_ms: i64,
    ) -> Option<String> {
        if rows <= 0 {
            return None;
        }
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.dropped_rows = inner.dropped_rows.wrapping_add(rows as i64);
        inner.dropped_by_reason[reason.tag() as usize] =
            inner.dropped_by_reason[reason.tag() as usize].wrapping_add(rows as i64);
        inner.last_drop = Some(format!("{table}:{}", reason.key()));
        let message = format!("dropped {rows} row(s) from {table} ({})", reason.key());
        warn_locked(&mut inner, &message, None, now_ms)
    }

    /// `onOpenFailure`: one more failed open, reported through the same window.
    pub fn on_open_failure(
        &self,
        message: &str,
        cause: Option<&str>,
        now_ms: i64,
    ) -> Option<String> {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.open_failures = inner.open_failures.wrapping_add(1);
        warn_locked(&mut inner, message, cause, now_ms)
    }

    /// `warn`: Some(line) when this call is the window's one report, None when it is suppressed.
    pub fn warn(&self, message: &str, cause: Option<&str>, now_ms: i64) -> Option<String> {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        warn_locked(&mut inner, message, cause, now_ms)
    }

    pub fn snapshot(&self) -> HealthSnapshot {
        let inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        HealthSnapshot {
            dropped_rows: inner.dropped_rows,
            dropped_by_reason: inner.dropped_by_reason,
            last_drop: inner.last_drop.clone().unwrap_or_default(),
            open_failures: inner.open_failures,
            suppressed: inner.suppressed,
            last_cause: inner.last_cause.clone().unwrap_or_default(),
        }
    }
}

/// The shared body of `onDropped` / `onOpenFailure` / `warn`.
fn warn_locked(
    inner: &mut Inner,
    message: &str,
    cause: Option<&str>,
    now_ms: i64,
) -> Option<String> {
    if let Some(cause) = cause {
        inner.last_cause = Some(cause.to_string());
    }
    if now_ms.wrapping_sub(inner.last_warn_at) < WARN_WINDOW_MS {
        inner.suppressed = inner.suppressed.wrapping_add(1);
        return None;
    }
    let more = std::mem::take(&mut inner.suppressed);
    let suffix = if more > 0 {
        format!(" (+{more} suppressed in {}s)", WARN_WINDOW_MS / 1000)
    } else {
        String::new()
    };
    inner.last_warn_at = now_ms;
    Some(format!("{message}{suffix}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_first_failure_of_a_window_is_reported_then_suppressed() {
        let health = Health::new();
        let line = health
            .on_dropped(3, DropReason::Overflow, "dns_log", 1_000_000)
            .unwrap();
        assert_eq!(line, "dropped 3 row(s) from dns_log (overflow)");

        assert_eq!(
            health.on_dropped(2, DropReason::Overflow, "dns_log", 1_030_000),
            None
        );
        assert_eq!(health.warn("stuck", None, 1_059_999), None);

        // One minute after the first line, the backlog is reported once with its count.
        let line = health
            .on_dropped(1, DropReason::Closed, "http_request_log", 1_060_000)
            .unwrap();
        assert_eq!(
            line,
            "dropped 1 row(s) from http_request_log (closed) (+2 suppressed in 60s)"
        );

        let snapshot = health.snapshot();
        assert_eq!(snapshot.dropped_rows, 6);
        assert_eq!(snapshot.dropped_by_reason, [5, 0, 0, 1]);
        assert_eq!(snapshot.last_drop, "http_request_log:closed");
        assert_eq!(snapshot.suppressed, 0);
    }

    #[test]
    fn zero_rows_count_nothing() {
        let health = Health::new();
        assert_eq!(
            health.on_dropped(0, DropReason::Overflow, "dns_log", 1),
            None
        );
        assert_eq!(
            health.on_dropped(-5, DropReason::Overflow, "dns_log", 1),
            None
        );
        assert_eq!(health.snapshot(), HealthSnapshot::default());
    }

    #[test]
    fn open_failures_keep_the_last_cause() {
        let health = Health::new();
        let line = health
            .on_open_failure(
                "unable to open diting_database",
                Some("SQLiteDatabaseLockedException: locked"),
                5_000_000,
            )
            .unwrap();
        assert_eq!(line, "unable to open diting_database");
        let snapshot = health.snapshot();
        assert_eq!(snapshot.open_failures, 1);
        assert_eq!(snapshot.last_cause, "SQLiteDatabaseLockedException: locked");

        // The cause of a suppressed line is still remembered.
        assert_eq!(
            health.on_open_failure(
                "unable to open diting_express",
                Some("IOException: gone"),
                5_001_000
            ),
            None
        );
        assert_eq!(health.snapshot().last_cause, "IOException: gone");
        assert_eq!(health.snapshot().suppressed, 1);
    }

    #[test]
    fn every_reason_has_its_kotlin_key_and_order() {
        assert_eq!(
            DropReason::ALL.map(|reason| reason.key()),
            ["overflow", "tableMissing", "noDatabase", "closed"]
        );
        for (index, reason) in DropReason::ALL.iter().enumerate() {
            assert_eq!(reason.tag() as usize, index);
            assert_eq!(DropReason::from_tag(index as u8), Some(*reason));
        }
        assert_eq!(DropReason::from_tag(4), None);
    }
}

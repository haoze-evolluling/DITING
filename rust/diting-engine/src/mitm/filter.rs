//! The MITM smart filter: `mitm_filter.go`'s log lines over the `diting-mitm-core` handle.
//!
//! Every decision already lives in the kernel: the per-UID allow list, the `path.Match` exclusion
//! patterns, the sensitive-host heuristics (banking, payment, identity), the automatic blacklist
//! with its failure streaks and the persistent `mitm_blacklist.txt` file. What Go kept was the
//! handle lifecycle and the log lines, and that is exactly what is left here — the engine has no
//! logcat bridge, so a line becomes a batch-log error row through `Engine::log_error`.
//!
//! The kernel is required for MITM: `Mitm::start` builds the filter before the session exists, and
//! a filter that cannot be built fails `StartStackMitm`. Nothing gets decrypted without it, which is
//! the conservative side of the old behaviour and loud instead of silent.

use std::time::Duration;

pub use diting_mitm_core::{BlacklistReport, FailureReport, Filter};

/// `logMitmBlacklisted`: the entry line plus, when the file append failed, the durability warning.
pub fn blacklist_lines(report: &BlacklistReport) -> Vec<String> {
    let mut lines = vec![format!(
        "MITM Filter: auto-blacklisted '{}' ({}, TTL={})",
        report.host,
        report.reason,
        go_duration(report.ttl_ms)
    )];
    if let Some(error) = &report.write_error {
        lines.push(format!(
            "MITM Filter: WARNING — cannot persist blacklist entry '{}': {error}",
            report.host
        ));
    }
    lines
}

/// `MitmFilter.RecordFailure`'s logging: a new entry, or the streak that is not there yet.
pub fn failure_lines(report: &FailureReport, error: &str) -> Vec<String> {
    if !report.recorded {
        return Vec::new();
    }
    if let Some(added) = &report.blacklist {
        return blacklist_lines(added);
    }
    if report.blacklisted {
        // A host that crossed the threshold earlier is already listed and already logged.
        return Vec::new();
    }
    vec![format!(
        "MITM Filter: recorded TLS failure for '{}' ({}/{}): {error}",
        report.host, report.count, report.threshold
    )]
}

/// `time.Duration.String()` for the console cadence Go printed (`168h0m0s`).
fn go_duration(millis: i64) -> String {
    let total = Duration::from_millis(millis.max(0) as u64);
    let seconds = total.as_secs();
    let hours = seconds / 3600;
    let minutes = (seconds % 3600) / 60;
    let rest = seconds % 60;
    let mut text = String::new();
    if hours > 0 {
        text.push_str(&format!("{hours}h"));
    }
    if hours > 0 || minutes > 0 {
        text.push_str(&format!("{minutes}m"));
    }
    text.push_str(&format!("{rest}s"));
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_week_reads_like_go_duration() {
        assert_eq!(go_duration(7 * 24 * 60 * 60 * 1000), "168h0m0s");
        assert_eq!(go_duration(90_500), "1m30s");
        assert_eq!(go_duration(1_500), "1s");
    }

    #[test]
    fn a_new_blacklist_entry_logs_the_file_warning_too() {
        let report = BlacklistReport {
            host: "bank.test".to_string(),
            reason: "EV certificate".to_string(),
            ttl_ms: 7 * 24 * 60 * 60 * 1000,
            write_error: Some("read-only".to_string()),
        };
        let lines = blacklist_lines(&report);
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("auto-blacklisted 'bank.test' (EV certificate, TTL=168h0m0s)"));
        assert!(lines[1].contains("cannot persist"));
    }
}

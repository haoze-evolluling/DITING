use std::time::Duration;

pub use diting_mitm_core::{BlacklistReport, FailureReport, Filter};

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

pub fn failure_lines(report: &FailureReport, error: &str) -> Vec<String> {
    if !report.recorded {
        return Vec::new();
    }
    if let Some(added) = &report.blacklist {
        return blacklist_lines(added);
    }
    if report.blacklisted {
        return Vec::new();
    }
    vec![format!(
        "MITM Filter: recorded TLS failure for '{}' ({}/{}): {error}",
        report.host, report.count, report.threshold
    )]
}

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

//! Row classification: the frozen markers that decide what a `dns_log` / `http_request_log` row
//! means. Labels stay in Dart (they are localised); the buckets are decided here once.

use serde_json::{json, Value};

/// A connection row, not a DNS query: `queryType = 0`, a `TCP `/`UDP ` name or the connection
/// marker in the message.
pub fn dns_is_connection(query_type: i64, query_name: &str, message: Option<&str>) -> bool {
    query_type == 0
        || query_name.starts_with("TCP ")
        || query_name.starts_with("UDP ")
        || message.is_some_and(|text| text.contains("blocked_by=connection"))
}

pub fn dns_is_blocked(result: &str, message: Option<&str>) -> bool {
    result == "BLOCKED" || message.is_some_and(|text| text.contains("blocked_by=firewall:"))
}

pub fn dns_is_rewritten(result: &str, message: Option<&str>) -> bool {
    result == "REWRITTEN"
        || message.is_some_and(|text| {
            text.contains("blocked_by=rewrite=")
                || text.contains("matched rewrite rule")
                || text.contains("复写")
                || text.contains("覆写")
        })
}

/// Display bucket token for the dashboard (`LogRowStatus`): `passed|filtered|failed|bypassed|cached`.
pub fn dns_log_status(result: &str, is_connection: bool, cached: bool) -> &'static str {
    if result == "BLOCKED" {
        return "filtered";
    }
    if result == "ERROR" {
        return "failed";
    }
    if is_connection {
        return "bypassed";
    }
    if cached {
        return "cached";
    }
    "passed"
}

/// Request-page bucket token (`RequestStatus`): `passed|rewritten|blocked|error|bypassed`.
pub fn dns_request_status(
    result: &str,
    is_connection: bool,
    is_blocked: bool,
    is_rewritten: bool,
) -> &'static str {
    if is_connection {
        return if is_blocked { "blocked" } else { "bypassed" };
    }
    if is_rewritten {
        return "rewritten";
    }
    match result {
        "PASSED" => "passed",
        "BLOCKED" => "blocked",
        _ => "error",
    }
}

/// `statusOfOutcome`: the raw outcome to the request-page bucket.
pub fn http_request_status(outcome: &str) -> &'static str {
    match outcome {
        "allowed" => "passed",
        "rewritten" => "rewritten",
        "blocked" | "invalid" => "blocked",
        "passthrough" | "bypassed" | "unsupported_protocol" | "resource_bypass" => "bypassed",
        _ => "error",
    }
}

/// `httpRowStatusOf`: the dashboard folds `rewritten` into passed.
pub fn http_log_status(outcome: &str) -> &'static str {
    match outcome {
        "allowed" | "rewritten" => "passed",
        "blocked" | "invalid" => "filtered",
        "passthrough" | "bypassed" | "unsupported_protocol" | "resource_bypass" => "bypassed",
        _ => "failed",
    }
}

pub fn http_outcome_is_passed(outcome: &str) -> bool {
    http_log_status(outcome) == "passed"
}

/// Parses a decimal integer the way Dart's `int.tryParse` does for these values: optional sign,
/// then digits, and nothing else.
fn try_parse_int(value: &str) -> Option<i64> {
    let bytes = value.as_bytes();
    let (sign, digits) = match bytes.first() {
        Some(b'+') => (1i64, &bytes[1..]),
        Some(b'-') => (-1i64, &bytes[1..]),
        _ => (1i64, bytes),
    };
    if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
        return None;
    }
    let mut number = 0i64;
    for digit in digits {
        number = number.checked_mul(10)?.checked_add((digit - b'0') as i64)?;
    }
    Some(sign * number)
}

/// `DnsLogMessage.parse`: comma tokens split on their first `=`, known keys only, later values win.
pub fn dns_message(message: Option<&str>) -> Value {
    let mut app = None;
    let mut resolved = None;
    let mut blocked_by = None;
    let mut error = None;
    let mut elapsed = None;
    if let Some(message) = message.filter(|text| !text.is_empty()) {
        for raw in message.split(',') {
            let token = raw.trim();
            let Some(separator) = token.find('=') else {
                continue;
            };
            if separator == 0 {
                continue;
            }
            let key = token[..separator].trim();
            let value = token[separator + 1..].trim();
            if value.is_empty() {
                continue;
            }
            match key {
                "app" => app = Some(value.to_owned()),
                "resolved" => resolved = Some(value.to_owned()),
                "blocked_by" => blocked_by = Some(value.to_owned()),
                "error" => error = Some(value.to_owned()),
                "elapsed" => {
                    let digits = value.strip_suffix("ms").unwrap_or(value);
                    elapsed = try_parse_int(digits);
                }
                _ => {}
            }
        }
    }
    json!({
        "app": app,
        "resolved": resolved,
        "blockedBy": blocked_by,
        "error": error,
        "elapsedMs": elapsed,
    })
}

/// `elapsedMsOf`: first `elapsed=<digits>ms` anywhere in the message, non-negative.
pub fn elapsed_ms(message: Option<&str>) -> Option<i64> {
    let message = message.filter(|text| !text.is_empty())?;
    let mut start = 0;
    while let Some(index) = message[start..].find("elapsed=") {
        let at = start + index;
        let after = &message[at + "elapsed=".len()..];
        let digits = after.bytes().take_while(u8::is_ascii_digit).count();
        if digits > 0 && after[digits..].starts_with("ms") {
            return after[..digits].parse::<i64>().ok();
        }
        start = at + 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connection_markers() {
        assert!(dns_is_connection(0, "x", None));
        assert!(dns_is_connection(1, "TCP 1.1.1.1:443", None));
        assert!(dns_is_connection(1, "UDP 1.1.1.1:53", None));
        assert!(dns_is_connection(1, "x", Some("blocked_by=connection")));
        assert!(!dns_is_connection(1, "x", None));
    }

    #[test]
    fn rewrite_and_block_markers() {
        assert!(dns_is_rewritten("REWRITTEN", None));
        assert!(dns_is_rewritten("PASSED", Some("blocked_by=rewrite=a")));
        assert!(dns_is_rewritten("PASSED", Some("复写")));
        assert!(dns_is_rewritten("PASSED", Some("覆写")));
        assert!(!dns_is_rewritten("PASSED", Some("blocked_by=firewall:x")));
        assert!(dns_is_blocked("PASSED", Some("blocked_by=firewall:x")));
    }

    #[test]
    fn buckets() {
        assert_eq!(dns_log_status("BLOCKED", false, false), "filtered");
        assert_eq!(dns_log_status("ERROR", false, false), "failed");
        assert_eq!(dns_log_status("PASSED", true, false), "bypassed");
        assert_eq!(dns_log_status("PASSED", false, true), "cached");
        assert_eq!(dns_request_status("PASSED", false, false, false), "passed");
        assert_eq!(
            dns_request_status("PASSED", false, false, true),
            "rewritten"
        );
        assert_eq!(dns_request_status("PASSED", true, false, false), "bypassed");
        assert_eq!(dns_request_status("PASSED", true, true, false), "blocked");
        assert_eq!(http_request_status("rewritten"), "rewritten");
        assert_eq!(http_log_status("rewritten"), "passed");
        assert_eq!(http_request_status("invalid"), "blocked");
        assert_eq!(http_log_status("resource_bypass"), "bypassed");
        assert_eq!(http_request_status("whatever"), "error");
        assert_eq!(http_log_status("whatever"), "failed");
    }

    #[test]
    fn message_tokens() {
        let message = dns_message(Some(
            " app = com.x , resolved=1.2.3.4, blocked_by=rule, elapsed=28ms, elapsed=-3ms, unknown=x, empty=",
        ));
        assert_eq!(message["app"], json!("com.x"));
        assert_eq!(message["resolved"], json!("1.2.3.4"));
        assert_eq!(message["blockedBy"], json!("rule"));
        assert_eq!(message["elapsedMs"], json!(-3));
        assert_eq!(dns_message(None)["app"], Value::Null);
    }

    #[test]
    fn elapsed_pattern() {
        assert_eq!(elapsed_ms(Some("elapsed=123ms")), Some(123));
        assert_eq!(elapsed_ms(Some("a elapsed=0ms b elapsed=9ms")), Some(0));
        assert_eq!(elapsed_ms(Some("elapsed=ms")), None);
        assert_eq!(elapsed_ms(Some("elapsed=12")), None);
        assert_eq!(elapsed_ms(Some("elapsed=-3ms")), None);
        assert_eq!(elapsed_ms(None), None);
    }
}

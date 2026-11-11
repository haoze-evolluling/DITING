use super::*;

#[test]
fn only_200_is_a_body_and_403_is_the_rate_limit() {
    assert_eq!(status_kind(200), StatusKind::Ok);
    assert_eq!(status_kind(403), StatusKind::RateLimited);
    for status in [0, 201, 204, 301, 400, 404, 429, 500, 502] {
        assert_eq!(status_kind(status), StatusKind::Other, "status {status}");
    }
}

#[test]
fn the_eof_retry_happens_once_and_only_for_eof() {
    assert!(should_retry(
        1,
        "Post \"https://dns.example/dns-query\": EOF"
    ));
    assert!(should_retry(1, "http2: server sent unexpected EOF"));
    assert!(!should_retry(2, "EOF"));
    // Case-sensitive, like `strings.Contains(errStr, "EOF")`.
    assert!(!should_retry(1, "eof"));
    assert!(!should_retry(1, "connection refused"));
    assert!(!should_retry(1, ""));
}

#[test]
fn a_zero_attempt_is_not_retried() {
    assert!(!should_retry(0, "EOF"));
}

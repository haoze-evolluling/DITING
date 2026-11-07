//! The HTTP sniffer's fixed cases: method gate, header walk, whitespace trimming and the two
//! Unicode details that make the port byte-exact.

use crate::http::{go_trim_space_bytes, looks_like_http_request, parse_http_host};

#[test]
fn recognizes_a_plain_request() {
    let request = b"GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n";
    assert!(looks_like_http_request(request));
    assert_eq!(parse_http_host(request), b"example.com");
}

#[test]
fn recognizes_lowercase_methods() {
    assert!(looks_like_http_request(b"get /x HTTP/1.0\r\n\r\n"));
}

#[test]
fn rejects_a_method_longer_than_the_scan_window() {
    assert!(!looks_like_http_request(
        b"ABCDEFGHIJKLMNOP / HTTP/1.1\r\n\r\n"
    ));
    assert!(looks_like_http_request(
        b"ABCDEFGHIJKLMNO / HTTP/1.1\r\n\r\n"
    ));
}

#[test]
fn rejects_non_letter_methods_and_missing_targets() {
    assert!(!looks_like_http_request(b"G3T / HTTP/1.1\r\n\r\n"));
    assert!(!looks_like_http_request(b"GET HTTP/1.1\r\n\r\n"));
    assert!(!looks_like_http_request(b"PRI * HTTP/2.0\r\n\r\n"));
    assert!(!looks_like_http_request(b"GET /\n"));
}

#[test]
fn host_value_is_trimmed_and_loses_its_port() {
    let request = b"GET / HTTP/1.1\r\nAccept: */*\r\nHost:  ads.example.com:8080  \r\n\r\n";
    assert_eq!(parse_http_host(request), b"ads.example.com");
}

#[test]
fn host_name_comparison_folds_like_go() {
    for header in [
        &b"Host: example.com"[..],
        &b"host: example.com"[..],
        &b"HOST: example.com"[..],
    ] {
        let mut request = b"GET / HTTP/1.1\r\n".to_vec();
        request.extend_from_slice(header);
        request.extend_from_slice(b"\r\n\r\n");
        assert_eq!(parse_http_host(&request), b"example.com");
    }

    // U+017F folds to `s`; Go's EqualFold accepts it and so must the kernel.
    let mut request = b"GET / HTTP/1.1\r\nHo\xc5\xbft: fold.example\r\n\r\n".to_vec();
    request.extend_from_slice(b"");
    assert_eq!(parse_http_host(&request), b"fold.example");
}

#[test]
fn headers_need_crlf_termination() {
    assert_eq!(
        parse_http_host(b"GET / HTTP/1.1\nHost: example.com\n\n"),
        b""
    );
    assert_eq!(parse_http_host(b"GET / HTTP/1.1\r\nHost: example.com"), b"");
}

#[test]
fn lines_without_a_name_are_skipped() {
    let request =
        b"GET / HTTP/1.1\r\n:value\r\nHost : skipped.example\r\nHost: kept.example\r\n\r\n";
    assert_eq!(parse_http_host(request), b"kept.example");
}

#[test]
fn a_colon_inside_the_value_cuts_it() {
    assert_eq!(parse_http_host(b"GET / HTTP/1.1\r\nHost: ::1\r\n\r\n"), b"");
}

#[test]
fn invalid_utf8_bytes_survive_trimming() {
    let mut request = b"GET / HTTP/1.1\r\nHost: ".to_vec();
    request.extend_from_slice(&[0xff, 0xfe]);
    request.extend_from_slice(b"\r\n\r\n");
    assert_eq!(parse_http_host(&request), &[0xff, 0xfe]);
}

#[test]
fn trimming_matches_go_on_bytes_and_runes() {
    assert_eq!(go_trim_space_bytes(b"  value \t\r\n"), b"value");
    assert_eq!(
        go_trim_space_bytes("\u{00a0}value\u{2028}".as_bytes()),
        b"value"
    );
    assert_eq!(
        go_trim_space_bytes(&[0xff, b' ', 0xff]),
        &[0xff, b' ', 0xff]
    );
    assert_eq!(go_trim_space_bytes(&[b' ', 0xff, b' ']), &[0xff]);
}

#[test]
fn an_empty_value_yields_an_empty_host() {
    assert_eq!(parse_http_host(b"GET / HTTP/1.1\r\nHost:\r\n\r\n"), b"");
    assert_eq!(
        parse_http_host(b"GET / HTTP/1.1\r\nAccept: */*\r\n\r\n"),
        b""
    );
}

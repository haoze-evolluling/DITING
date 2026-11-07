//! The CONNECT bytes, including the headers `net/http` adds on its own.

use super::*;

#[test]
fn plain_connect_matches_request_write() {
    let request = connect_request("example.com:443", "", "");
    assert_eq!(
        String::from_utf8(request).unwrap(),
        "CONNECT example.com:443 HTTP/1.1\r\n\
         Host: example.com:443\r\n\
         User-Agent: Go-http-client/1.1\r\n\
         \r\n"
    );
}

#[test]
fn credentials_are_standard_base64() {
    let text = String::from_utf8(connect_request("example.com:443", "alice", "s3cret")).unwrap();
    let expected_prefix = "CONNECT example.com:443 HTTP/1.1\r\n\
         Host: example.com:443\r\n\
         User-Agent: Go-http-client/1.1\r\n\
         Proxy-Authorization: Basic ";
    let token = text
        .strip_prefix(expected_prefix)
        .and_then(|rest| rest.strip_suffix("\r\n\r\n"))
        .expect("the authorization header must precede the blank line");
    // Standard alphabet with padding (no `-`/`_`), and it carries `user:pass`.
    assert!(!token.contains('-') && !token.contains('_'), "{token}");
    assert_eq!(token.len() % 4, 0);
}

#[test]
fn an_empty_username_or_password_still_authenticates() {
    // The old condition was `username != "" || password != ""`.
    for (user, pass) in [("only-user", ""), ("", "only-pass")] {
        let text = String::from_utf8(connect_request("h:1", user, pass)).unwrap();
        assert!(text.contains("Proxy-Authorization: Basic "), "{text}");
    }
    let plain = String::from_utf8(connect_request("h:1", "", "")).unwrap();
    assert!(!plain.contains("Proxy-Authorization"), "{plain}");
}

#[test]
fn target_is_written_verbatim() {
    let text = String::from_utf8(connect_request("[::1]:443", "", "")).unwrap();
    assert!(
        text.starts_with("CONNECT [::1]:443 HTTP/1.1\r\nHost: [::1]:443\r\n"),
        "{text}"
    );
}

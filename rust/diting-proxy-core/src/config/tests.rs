//! The normalization rules, including the error texts the UI shows verbatim.

use super::*;

fn config(protocol: &str, host: &str, port: i64) -> ProxyConfig {
    ProxyConfig {
        enabled: true,
        protocol: protocol.to_string(),
        host: host.to_string(),
        port,
        ..ProxyConfig::default()
    }
}

#[test]
fn normalizes_protocol_host_scope_and_uids() {
    let mut input = config(" SOCKS5 ", " 127.0.0.1 ", 1080);
    input.scope = "APPS".to_string();
    input.uids = vec![10001, 0, -3, 10001, 10002];
    let out = normalize(input).unwrap();
    assert_eq!(out.protocol, "socks5");
    assert_eq!(out.host, "127.0.0.1");
    assert_eq!(out.scope, SCOPE_APPS);
    assert_eq!(out.uids, vec![10001, 10002]);
    assert!(out.per_app());

    let out = normalize(config("Http", "::1", 8080)).unwrap();
    assert_eq!(out.protocol, "http");
    assert_eq!(out.host, "::1");
    assert_eq!(out.scope, SCOPE_ALL);
    assert!(out.uids.is_empty());
}

#[test]
fn host_is_stored_in_ip_string_form() {
    for (input, expected) in [
        ("0:0:0:0:0:0:0:1", "::1"),
        ("::ffff:127.0.0.1", "127.0.0.1"),
        ("127.000.000.001", ""),
        ("::1", "::1"),
    ] {
        let result = normalize(config("socks5", input, 9));
        if expected.is_empty() {
            assert!(result.is_err(), "{input} must be rejected");
        } else {
            assert_eq!(result.unwrap().host, expected);
        }
    }
}

#[test]
fn rejects_invalid_fields_in_the_original_order() {
    // Protocol first, so a bad protocol hides a bad host.
    assert_eq!(
        normalize(config("socks4", "8.8.8.8", 0)).unwrap_err(),
        "unsupported outbound proxy protocol \"socks4\""
    );
    assert_eq!(
        normalize(config("", "127.0.0.1", 1080)).unwrap_err(),
        "unsupported outbound proxy protocol \"\""
    );
    for host in ["8.8.8.8", "not-an-ip", "", "  "] {
        assert_eq!(
            normalize(config("socks5", host, 1080)).unwrap_err(),
            "outbound proxy host must be 127.0.0.1 or ::1",
            "host {host:?}"
        );
    }
    for port in [0, 65536, -1] {
        assert_eq!(
            normalize(config("socks5", "127.0.0.1", port)).unwrap_err(),
            "outbound proxy port must be between 1 and 65535",
            "port {port}"
        );
    }
    assert_eq!(
        normalize(config("socks5", "127.0.0.1", 65535))
            .unwrap()
            .port,
        65535
    );
}

#[test]
fn credential_length_is_measured_in_bytes() {
    let mut ok = config("socks5", "127.0.0.1", 1080);
    ok.username = "u".repeat(255);
    assert!(normalize(ok).is_ok());

    let mut long_user = config("socks5", "127.0.0.1", 1080);
    long_user.username = "u".repeat(256);
    assert_eq!(
        normalize(long_user).unwrap_err(),
        "SOCKS5 credentials must not exceed 255 bytes"
    );

    let mut long_pass = config("socks5", "127.0.0.1", 1080);
    long_pass.password = "p".repeat(256);
    assert_eq!(
        normalize(long_pass).unwrap_err(),
        "SOCKS5 credentials must not exceed 255 bytes"
    );
}

#[test]
fn unknown_scope_falls_back_to_all() {
    let mut input = config("socks5", "127.0.0.1", 1080);
    input.scope = " Weird ".to_string();
    assert_eq!(normalize(input).unwrap().scope, SCOPE_ALL);
}

#[test]
fn disabled_config_is_returned_untouched() {
    let mut input = config("bogus", "8.8.8.8", 0);
    input.enabled = false;
    input.scope = "Weird".to_string();
    input.uids = vec![5];
    let out = normalize(input).unwrap();
    assert!(!out.enabled);
    assert_eq!(out.protocol, "bogus");
    assert_eq!(out.host, "8.8.8.8");
    assert_eq!(out.port, 0);
    assert_eq!(out.scope, "Weird");
    assert!(out.uids.is_empty());
    assert!(!out.per_app());
}

#[test]
fn protocol_whitespace_is_trimmed_before_the_error_text() {
    assert_eq!(
        normalize(config(" Socks4 ", "127.0.0.1", 1080)).unwrap_err(),
        "unsupported outbound proxy protocol \"socks4\""
    );
}

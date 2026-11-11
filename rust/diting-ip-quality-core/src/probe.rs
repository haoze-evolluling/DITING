//! The egress-IP probe: a source answers either a bare address or `{"ip": "..."}`, and a captive
//! portal's HTML must not be mistaken for one.

use serde_json::Value;

/// Long enough for a full IPv6 address; anything longer is a page, not an address.
const MAX_IP_LENGTH: usize = 45;

/// Same gate as the legacy `_isIpLike`: ASCII hex digits, dots and colons only.
pub fn is_ip_like(value: &str) -> bool {
    if value.is_empty() || value.len() > MAX_IP_LENGTH {
        return false;
    }
    value
        .bytes()
        .all(|byte| byte.is_ascii_hexdigit() || byte == b'.' || byte == b':')
}

/// Reads the egress IP out of one probe body; `None` means "this endpoint did not answer".
pub fn parse_probe(body: &str) -> Option<String> {
    let raw = body.trim();
    if raw.starts_with('{') {
        let decoded: Value = serde_json::from_str(raw).ok()?;
        let ip = decoded.as_object()?.get("ip")?.as_str()?.trim();
        return is_ip_like(ip).then(|| ip.to_owned());
    }
    is_ip_like(raw).then(|| raw.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_and_json_bodies_are_both_read() {
        assert_eq!(parse_probe(" 9.9.9.9\n").as_deref(), Some("9.9.9.9"));
        assert_eq!(
            parse_probe(r#"{"ip":"2001:4860:4860::8888"}"#).as_deref(),
            Some("2001:4860:4860::8888")
        );
        assert_eq!(
            parse_probe(r#"{ "ip" : " 1.2.3.4 " }"#).as_deref(),
            Some("1.2.3.4")
        );
    }

    #[test]
    fn html_and_malformed_json_are_rejected() {
        for body in [
            "<html><body>captive portal</body></html>",
            "rate limited",
            r#"{"address":"1.2.3.4"}"#,
            r#"{"ip":1234}"#,
            r#"{"ip":"not-an-ip"}"#,
            "{}",
            "",
            "1234567890123456789012345678901234567890123456",
        ] {
            assert_eq!(parse_probe(body), None, "{body}");
        }
    }

    #[test]
    fn ip_like_matches_the_legacy_gate() {
        assert!(is_ip_like("1.2.3.4"));
        assert!(is_ip_like("::1"));
        assert!(is_ip_like("2001:db8::"));
        assert!(!is_ip_like("localhost"));
        assert!(!is_ip_like("[::1]"));
        assert!(!is_ip_like("1.2.3.4 "));
        assert!(!is_ip_like(""));
    }
}

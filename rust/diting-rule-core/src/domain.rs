//! Domain normalization and literal-IP checks; a port of `rule_domain_utils.dart`.
//!
//! Anything undecidable returns `None` so the rule counts as invalid instead of never matching.
//! The Dart original leans on `dart:io` (`InternetAddress`) and `Uri`; both are mimicked here with
//! `std` only, including the quirks the parity tests lock down:
//!
//! * `InternetAddress.address` echoes the input text (no IPv6 compression, case preserved), so a
//!   literal IP is returned trimmed and otherwise untouched.
//! * A non-ASCII candidate goes through `Uri.parse`, which percent-encodes it and therefore makes
//!   every label invalid — except when the non-ASCII part sits behind `#`, `?`, `\` (fragment /
//!   query / terminator) or in the userinfo, which is what [`to_ascii_lower`] reproduces.

/// Sinkhole addresses: these hosts targets mean "block", not "rewrite".
pub const SINKHOLE_ADDRESSES: [&str; 5] = ["0", "0.0.0.0", "127.0.0.1", "::", "::1"];

pub const VALID_DNS_TYPES: [&str; 15] = [
    "A", "AAAA", "CNAME", "HTTPS", "SVCB", "TXT", "MX", "PTR", "SRV", "SOA", "NS", "ANY", "CAA",
    "DS", "DNSKEY",
];

const WEB_ONLY_MODIFIER_PREFIXES: &[&str] = &[
    "domain=",
    "~domain=",
    "to=",
    "~to=",
    "method=",
    "~method=",
    "header=",
    "~header=",
    "redirect=",
    "redirect-rule=",
    "removeparam=",
    "removeheader=",
    "replace=",
    "urltransform=",
    "cookie=",
    "csp=",
    "permissions=",
    "jsonprune=",
    "xmlprune=",
    "referrerpolicy=",
    "reason=",
];

const WEB_ONLY_MODIFIER_TOKENS: &[&str] = &[
    "third-party",
    "~third-party",
    "strict-third-party",
    "strict-first-party",
    "match-case",
    "network",
    "document",
    "~document",
    "subdocument",
    "~subdocument",
    "script",
    "~script",
    "stylesheet",
    "~stylesheet",
    "image",
    "~image",
    "font",
    "~font",
    "media",
    "~media",
    "object",
    "~object",
    "xmlhttprequest",
    "~xmlhttprequest",
    "websocket",
    "~websocket",
    "ping",
    "~ping",
    "other",
    "~other",
    "popup",
    "~popup",
    "elemhide",
    "ehide",
    "generichide",
    "ghide",
    "specifichide",
    "shide",
    "genericblock",
    "urlblock",
    "content",
    "jsinject",
    "extension",
    "hls",
    "inline-script",
    "inline-font",
];

/// `RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')` from the Dart original.
fn is_valid_label(label: &str) -> bool {
    let bytes = label.as_bytes();
    let alnum = |c: u8| c.is_ascii_lowercase() || c.is_ascii_digit();
    if bytes.is_empty() || !alnum(bytes[0]) {
        return false;
    }
    if bytes.len() == 1 {
        return true;
    }
    if !alnum(bytes[bytes.len() - 1]) {
        return false;
    }
    bytes[1..bytes.len() - 1]
        .iter()
        .all(|&c| alnum(c) || c == b'-')
}

/// Length in UTF-16 code units, which is what `String.length` counts in Dart.
pub fn utf16_len(value: &str) -> usize {
    if value.is_ascii() {
        return value.len();
    }
    value.encode_utf16().count()
}

/// Dart's `value.trim().replaceFirst(RegExp(r'\.+$'), '')`.
fn trim_and_strip_dots(value: &str) -> &str {
    value.trim().trim_end_matches('.')
}

fn has_rejected_separator(value: &str) -> bool {
    value.contains('/') || value.contains(':') || value.contains(' ')
}

/// `_toAsciiLower` without pulling in an IDNA crate: the percent-encoded result can never satisfy
/// the label regex, so a non-ASCII host is always rejected.
fn to_ascii_lower(value: &str) -> Option<String> {
    if value.is_ascii() {
        if value.bytes().any(|b| b < 0x21 || b == 0x7f) {
            return None;
        }
        return Some(value.to_ascii_lowercase());
    }
    let host_part = match value.find(['#', '?', '\\']) {
        Some(index) => &value[..index],
        None => value,
    };
    let host = match host_part.rfind('@') {
        Some(index) => &host_part[index + 1..],
        None => host_part,
    };
    if host.is_empty() || !host.is_ascii() || host.bytes().any(|b| b < 0x21 || b == 0x7f) {
        return None;
    }
    Some(host.to_ascii_lowercase())
}

/// Literal IPv4/IPv6, or an IPv6 literal with a numeric scope id (`fe80::1%1`).
fn parses_as_ip(value: &str) -> bool {
    if value.parse::<std::net::Ipv4Addr>().is_ok() || value.parse::<std::net::Ipv6Addr>().is_ok() {
        return true;
    }
    match value.rsplit_once('%') {
        Some((address, scope)) => {
            !scope.is_empty()
                && scope.bytes().all(|b| b.is_ascii_digit())
                && address.parse::<std::net::Ipv6Addr>().is_ok()
        }
        None => false,
    }
}

pub fn looks_like_literal_ip(value: &str) -> bool {
    let trimmed = value.trim();
    if trimmed.is_empty() || utf16_len(trimmed) > 45 {
        return false;
    }
    if trimmed == "0" {
        return true;
    }
    parses_as_ip(trimmed)
}

/// Literal IP text as Dart's `InternetAddress.address` would report it: the trimmed input with its
/// original case and no IPv6 compression.
pub fn parse_numeric_address_safe(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || utf16_len(trimmed) > 45 || !parses_as_ip(trimmed) {
        return None;
    }
    Some(trimmed.to_string())
}

pub fn normalize_domain(value: &str) -> Option<String> {
    let candidate = trim_and_strip_dots(value);
    if candidate.is_empty() || has_rejected_separator(candidate) {
        return None;
    }
    let ascii = to_ascii_lower(candidate)?;
    if ascii.len() > 253 || !ascii.contains('.') || looks_like_literal_ip(&ascii) {
        return None;
    }
    for label in ascii.split('.') {
        if label.is_empty() || label.len() > 63 || !is_valid_label(label) {
            return None;
        }
    }
    Some(ascii)
}

pub fn normalize_wildcard_domain(value: &str) -> Option<String> {
    let candidate = trim_and_strip_dots(value);
    if candidate.is_empty() || has_rejected_separator(candidate) {
        return None;
    }
    if candidate == "*" {
        return Some("*".to_string());
    }
    let lower = candidate.to_lowercase();
    if utf16_len(&lower) > 253 {
        return None;
    }
    for label in lower.split('.') {
        if label.is_empty() || utf16_len(label) > 63 {
            return None;
        }
        for unit in label.chars() {
            let allowed = unit.is_ascii_lowercase()
                || unit.is_ascii_digit()
                || unit == '-'
                || unit == '*'
                || unit == '_';
            if !allowed {
                return None;
            }
        }
    }
    Some(lower)
}

pub fn is_sinkhole(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    SINKHOLE_ADDRESSES.contains(&lower.as_str())
}

pub fn is_valid_dns_type(value: &str) -> bool {
    VALID_DNS_TYPES.contains(&value)
}

/// Modifiers that only matter for HTTP(S), not for DNS; such lines are valid rules the DNS layer
/// ignores.
pub fn is_web_only_modifier(lower: &str) -> bool {
    if WEB_ONLY_MODIFIER_TOKENS.contains(&lower) {
        return true;
    }
    WEB_ONLY_MODIFIER_PREFIXES
        .iter()
        .any(|prefix| lower.starts_with(prefix))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_domains() {
        assert_eq!(
            normalize_domain("Example.COM."),
            Some("example.com".to_string())
        );
        assert_eq!(normalize_domain(" a.com "), Some("a.com".to_string()));
        assert_eq!(normalize_domain("a..com"), None);
        assert_eq!(normalize_domain("...a.com"), None);
        assert_eq!(normalize_domain("-a.com"), None);
        assert_eq!(normalize_domain("a-.com"), None);
        assert_eq!(normalize_domain("a_b.com"), None);
        assert_eq!(normalize_domain("a.com"), Some("a.com".to_string()));
        assert_eq!(normalize_domain("localhost"), None);
        assert_eq!(normalize_domain("127.0.0.1"), None);
        assert_eq!(normalize_domain("中文.cn"), None);
        assert_eq!(normalize_domain("a.com/é"), None);
    }

    #[test]
    fn mirrors_uri_host_extraction_for_non_ascii() {
        // Dart returns the ASCII part when the non-ASCII text sits behind a fragment/query.
        assert_eq!(normalize_domain("a.com#é"), Some("a.com".to_string()));
        assert_eq!(normalize_domain("a.com?é"), Some("a.com".to_string()));
        assert_eq!(normalize_domain("a.com\\é"), Some("a.com".to_string()));
        assert_eq!(normalize_domain("é@a.com"), Some("a.com".to_string()));
        assert_eq!(normalize_domain("x@é.com"), None);
        assert_eq!(normalize_domain("a.com[é"), None);
    }

    #[test]
    fn normalizes_wildcard_domains() {
        assert_eq!(normalize_wildcard_domain("*"), Some("*".to_string()));
        assert_eq!(
            normalize_wildcard_domain("*.a.com"),
            Some("*.a.com".to_string())
        );
        assert_eq!(normalize_wildcard_domain("a.*"), Some("a.*".to_string()));
        assert_eq!(
            normalize_wildcard_domain("A.COM"),
            Some("a.com".to_string())
        );
        assert_eq!(normalize_wildcard_domain("a b.com"), None);
        assert_eq!(normalize_wildcard_domain("a..com"), None);
        // Wildcards skip the literal-IP and label-shape checks the plain form applies.
        assert_eq!(
            normalize_wildcard_domain("127.0.0.1"),
            Some("127.0.0.1".to_string())
        );
        assert_eq!(
            normalize_wildcard_domain("_dmarc.a.com"),
            Some("_dmarc.a.com".to_string())
        );
    }

    #[test]
    fn detects_literal_ips() {
        assert!(looks_like_literal_ip("1.2.3.4"));
        assert!(looks_like_literal_ip("::1"));
        assert!(looks_like_literal_ip("0"));
        assert!(!looks_like_literal_ip("01.2.3.4"));
        assert!(!looks_like_literal_ip("1.2.3.4.5"));
        assert_eq!(
            parse_numeric_address_safe("1.2.3.4"),
            Some("1.2.3.4".to_string())
        );
        // The address echoes the input, so case and the uncompressed form survive.
        assert_eq!(
            parse_numeric_address_safe("2001:DB8::1"),
            Some("2001:DB8::1".to_string())
        );
        assert_eq!(
            parse_numeric_address_safe("fe80::1%1"),
            Some("fe80::1%1".to_string())
        );
        assert_eq!(parse_numeric_address_safe("fe80::1%eth0"), None);
        assert_eq!(parse_numeric_address_safe("0"), None);
    }

    #[test]
    fn classifies_web_only_modifiers() {
        assert!(is_web_only_modifier("third-party"));
        assert!(is_web_only_modifier("~document"));
        assert!(is_web_only_modifier("removeparam=utm_source"));
        assert!(!is_web_only_modifier("important"));
    }
}

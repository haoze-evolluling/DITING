pub fn sanitize(input: &str) -> String {
    let mut value = input.trim();
    if value.is_empty() {
        return String::new();
    }

    if let Some(index) = value.find("://") {
        value = &value[index + 3..];
    }
    if let Some(index) = value.find(['/', '?', '#']) {
        value = &value[..index];
    }
    if let Some(index) = value.rfind('@') {
        value = &value[index + 1..];
    }

    if let Some(rest) = value.strip_prefix('[') {
        return match rest.find(']') {
            Some(end) => rest[..end].to_string(),
            None => value.to_string(),
        };
    }

    if !value.contains("::") && value.matches(':').count() == 1 {
        let (host, port) = value.split_once(':').unwrap_or((value, ""));
        if !port.is_empty() && port.chars().all(is_ascii_digit) {
            return host.to_string();
        }
    }

    value.to_string()
}

pub fn is_ip_literal(value: &str) -> bool {
    let text = value.strip_prefix('[').unwrap_or(value);
    let text = text.strip_suffix(']').unwrap_or(text);
    if text.is_empty() {
        return false;
    }

    if !text.contains(':') {
        let parts: Vec<&str> = text.split('.').collect();
        if parts.len() != 4 {
            return false;
        }
        return parts.iter().all(|part| {
            !part.is_empty()
                && part.len() <= 3
                && part.chars().all(is_ascii_digit)
                && part.parse::<u32>().is_ok_and(|value| value <= 255)
        });
    }

    if text.matches(':').count() < 2 {
        return false;
    }
    text.chars()
        .all(|c| is_ascii_digit(c) || c.is_ascii_hexdigit() || c == ':' || c == '.')
}

fn is_ascii_digit(c: char) -> bool {
    c.is_ascii_digit()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_strips_the_parts_of_a_url() {
        assert_eq!(
            sanitize("  https://user:pw@dns.google:8443/dns-query?x=1#f  "),
            "dns.google"
        );
        assert_eq!(sanitize("dns.google"), "dns.google");
        assert_eq!(sanitize("dns.google:53"), "dns.google");
        assert_eq!(sanitize("dns.google:port"), "dns.google:port");
        assert_eq!(sanitize("example.com/path"), "example.com");
        assert_eq!(sanitize(""), "");
        assert_eq!(sanitize("   "), "");
    }

    #[test]
    fn sanitize_keeps_ipv6_intact() {
        assert_eq!(sanitize("2001:db8::1"), "2001:db8::1");
        assert_eq!(sanitize("[2001:db8::1]:53"), "2001:db8::1");
        assert_eq!(sanitize("[2001:db8::1]"), "2001:db8::1");
        assert_eq!(sanitize("[]"), "");
        assert_eq!(sanitize("[::1"), "[::1");
    }

    #[test]
    fn is_ip_literal_accepts_only_literal_shapes() {
        for value in ["1.2.3.4", "010.0.0.1", "255.255.255.255", "[1.2.3.4]"] {
            assert!(is_ip_literal(value), "{value}");
        }
        for value in [
            "",
            "1.2.3",
            "1.2.3.4.5",
            "256.0.0.1",
            "1.2.3.04x",
            "1.2.3.",
            "dns.google",
        ] {
            assert!(!is_ip_literal(value), "{value}");
        }
        for value in [
            "::",
            "::1",
            "2001:db8::1",
            "[2001:db8::1]",
            "2001:4860:4860::8888",
        ] {
            assert!(is_ip_literal(value), "{value}");
        }
        for value in [":1", "1:2", "2001:db8::zz", "dns.google:53"] {
            assert!(!is_ip_literal(value), "{value}");
        }
    }
}

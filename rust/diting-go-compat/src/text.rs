use std::borrow::Cow;

fn go_lower_char(c: char) -> char {
    match c {
        '\u{0130}' => 'i',
        _ => c.to_lowercase().next().unwrap_or(c),
    }
}

pub fn go_lower(s: &str) -> Cow<'_, str> {
    if s.is_ascii() {
        if s.bytes().any(|byte| byte.is_ascii_uppercase()) {
            return Cow::Owned(s.to_ascii_lowercase());
        }
        return Cow::Borrowed(s);
    }
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        out.push(go_lower_char(c));
    }
    Cow::Owned(out)
}

fn go_upper_char(c: char) -> char {
    let mut upper = c.to_uppercase();
    match (upper.next(), upper.next()) {
        (Some(single), None) => single,
        _ => c,
    }
}

pub fn go_upper(s: &str) -> Cow<'_, str> {
    if s.is_ascii() {
        if s.bytes().any(|byte| byte.is_ascii_lowercase()) {
            return Cow::Owned(s.to_ascii_uppercase());
        }
        return Cow::Borrowed(s);
    }
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        out.push(go_upper_char(c));
    }
    Cow::Owned(out)
}

pub fn go_trim_space(s: &str) -> &str {
    s.trim_matches(char::is_whitespace)
}

pub fn normalize_domain(domain: &str) -> Cow<'_, str> {
    let canonical = !domain
        .bytes()
        .any(|byte| byte.is_ascii_uppercase() || byte >= 0x80 || byte <= b' ');
    let lowered = if canonical {
        Cow::Borrowed(domain)
    } else {
        go_lower(go_trim_space(domain))
    };
    match lowered {
        Cow::Borrowed(value) => Cow::Borrowed(value.strip_suffix('.').unwrap_or(value)),
        Cow::Owned(value) => match value.strip_suffix('.') {
            Some(trimmed) => Cow::Owned(trimmed.to_string()),
            None => Cow::Owned(value),
        },
    }
}

pub fn go_lower_trim(s: &str) -> String {
    go_lower(go_trim_space(s)).into_owned()
}

pub fn go_lower_trim_dot(s: &str) -> String {
    let lowered = go_lower_trim(s);
    match lowered.strip_suffix('.') {
        Some(trimmed) => trimmed.to_string(),
        None => lowered,
    }
}

pub fn has_fold_prefix(s: &str) -> bool {
    s.starts_with("(?i)")
}

pub fn domain_or_suffix(domain: &str, pattern: &str) -> bool {
    domain == pattern
        || (domain.len() > pattern.len()
            && domain.ends_with(pattern)
            && domain.as_bytes()[domain.len() - pattern.len() - 1] == b'.')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lower_matches_go_simple_folding() {
        assert_eq!(go_lower("AbC"), "abc");
        assert_eq!(go_lower("\u{0130}STANBUL"), "istanbul");
        assert_eq!(go_lower("ΑΣ"), "ασ");
        assert_eq!(go_lower("Straße"), "straße");
    }

    #[test]
    fn upper_matches_go_simple_folding() {
        assert_eq!(go_upper("aBc"), "ABC");
        assert_eq!(go_upper("straße"), "STRAßE");
        assert_eq!(go_upper("ﬁle"), "ﬁLE");
        assert!(matches!(go_upper("ABC"), Cow::Borrowed(_)));
    }

    #[test]
    fn trim_and_dot_helpers() {
        assert_eq!(go_lower_trim("  Example.COM \t"), "example.com");
        assert_eq!(go_lower_trim_dot(" Example.COM. "), "example.com");
        assert_eq!(go_lower_trim_dot("example.com.."), "example.com.");
    }

    #[test]
    fn normalize_domain_matches_the_go_helper() {
        assert!(matches!(normalize_domain("example.com"), Cow::Borrowed(_)));
        assert_eq!(normalize_domain("Example.COM."), "example.com");
        assert_eq!(normalize_domain("  ads.example.com.\t"), "ads.example.com");
        assert_eq!(normalize_domain("ΑΣ.com"), "ασ.com");
        assert_eq!(normalize_domain("\u{130}stanbul.com"), "istanbul.com");
        assert_eq!(normalize_domain("example.com.."), "example.com.");
        assert_eq!(normalize_domain("."), "");
        assert_eq!(normalize_domain("   "), "");
    }

    #[test]
    fn suffix_matching_needs_a_label_boundary() {
        assert!(domain_or_suffix("example.com", "example.com"));
        assert!(domain_or_suffix("ads.example.com", "example.com"));
        assert!(!domain_or_suffix("notexample.com", "example.com"));
        assert!(!domain_or_suffix("example.co", "example.com"));
    }
}

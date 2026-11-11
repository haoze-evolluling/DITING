//! Subscription URL rules: the frozen placeholder set, the Java `URLEncoder` spelling of
//! `{urlEncoded}`, name/line derivations and the validation order.
//!
//! URI parsing stays in Dart (`Uri`): the caller passes the already-normalised components
//! (`scheme` / `host` / `path` / `query`) and this module owns every rule applied on top of them.

use serde_json::Value;

use crate::payload;

/// Placeholders a mirror template may use; the set is persisted, so it never grows silently.
pub const PLACEHOLDERS: [&str; 6] = [
    "{url}",
    "{urlEncoded}",
    "{scheme}",
    "{host}",
    "{path}",
    "{pathAndQuery}",
];

/// Validation failures, mapped to l10n sentences by the Dart caller.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UrlError {
    Empty,
    BadFormat,
    NotHttp,
    NoHost,
}

impl UrlError {
    pub fn as_str(self) -> &'static str {
        match self {
            UrlError::Empty => "empty",
            UrlError::BadFormat => "badFormat",
            UrlError::NotHttp => "notHttp",
            UrlError::NoHost => "noHost",
        }
    }
}

impl AsRef<str> for UrlError {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}

/// Mirror-template failures.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MirrorError {
    /// No known placeholder is present.
    Placeholder,
    /// The built address does not start with `http://` or `https://`.
    Scheme,
}

impl MirrorError {
    pub fn as_str(self) -> &'static str {
        match self {
            MirrorError::Placeholder => "placeholder",
            MirrorError::Scheme => "scheme",
        }
    }
}

impl AsRef<str> for MirrorError {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}

/// The components Dart's `Uri` resolved for one address.
#[derive(Debug, Default, Clone)]
pub struct UrlParts {
    pub parsed: bool,
    pub has_scheme: bool,
    pub scheme: String,
    pub host: String,
    pub path: String,
    pub query: String,
}

impl UrlParts {
    pub fn from(value: &Value) -> Self {
        let parts = Value::Object(payload::child(value, "urlParts").clone());
        Self {
            parsed: payload::flag(parts.get("parsed")).unwrap_or(false),
            has_scheme: payload::flag(parts.get("hasScheme")).unwrap_or(false),
            scheme: payload::text_or_empty(&parts, "scheme"),
            host: payload::text_or_empty(&parts, "host"),
            path: payload::text_or_empty(&parts, "path"),
            query: payload::text_or_empty(&parts, "query"),
        }
    }

    fn path_and_query(&self) -> String {
        if self.query.is_empty() {
            self.path.clone()
        } else {
            format!("{}?{}", self.path, self.query)
        }
    }
}

/// The trimmed address is empty, not absolute, not HTTP(S), or has no host — in that order.
pub fn validate(address: &str, parts: &UrlParts) -> Result<(), UrlError> {
    if address.trim().is_empty() {
        return Err(UrlError::Empty);
    }
    if !parts.parsed || !parts.has_scheme {
        return Err(UrlError::BadFormat);
    }
    if parts.scheme != "https" && parts.scheme != "http" {
        return Err(UrlError::NotHttp);
    }
    if parts.host.is_empty() {
        return Err(UrlError::NoHost);
    }
    Ok(())
}

/// File name of the last path segment, else the host, else the raw address.
pub fn extract_name(address: &str, path: &str, host: &str) -> String {
    let file = match path.rfind('/') {
        Some(index) => &path[index + 1..],
        None => path,
    };
    if !file.trim().is_empty() {
        return file.to_owned();
    }
    if !host.is_empty() {
        return host.to_owned();
    }
    address.to_owned()
}

/// Lexical effective lines: non-empty after trimming, and not a `!` / `#` / `//` comment.
pub fn count_effective_lines(content: &str) -> i64 {
    let mut count = 0i64;
    for raw in content.split('\n') {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('!') || line.starts_with('#') || line.starts_with("//") {
            continue;
        }
        count += 1;
    }
    count
}

/// Trims a template, requires one known placeholder, and proves it can build an address.
///
/// `None` means there is no template; a malformed one is an error the edit sheet shows.
pub fn normalize_template(template: Option<&str>) -> Result<Option<String>, MirrorError> {
    let Some(trimmed) = template.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    if !PLACEHOLDERS
        .iter()
        .any(|placeholder| trimmed.contains(placeholder))
    {
        return Err(MirrorError::Placeholder);
    }
    let example = UrlParts {
        parsed: true,
        has_scheme: true,
        scheme: "https".to_owned(),
        host: "example.com".to_owned(),
        path: "/rules.txt".to_owned(),
        query: String::new(),
    };
    build_mirror(trimmed, "https://example.com/rules.txt", &example)?;
    Ok(Some(trimmed.to_owned()))
}

/// Replaces every placeholder in the legacy order: `{urlEncoded}`, `{url}`, `{scheme}`, `{host}`,
/// `{pathAndQuery}`, `{path}`. The order is part of the contract because `{url}` may itself contain
/// a later placeholder.
pub fn build_mirror(
    template: &str,
    original: &str,
    parts: &UrlParts,
) -> Result<String, MirrorError> {
    let path_and_query = parts.path_and_query();
    let result = template
        .replace("{urlEncoded}", &encode_java_url_encoder(original))
        .replace("{url}", original)
        .replace("{scheme}", &parts.scheme)
        .replace("{host}", &parts.host)
        .replace("{pathAndQuery}", &path_and_query)
        .replace("{path}", &parts.path);
    if !result.starts_with("https://") && !result.starts_with("http://") {
        return Err(MirrorError::Scheme);
    }
    Ok(result)
}

/// A template that applies to this address, or `None` when it is absent, unparsable or malformed.
pub fn mirror_url_of(template: Option<&str>, original: &str, parts: &UrlParts) -> Option<String> {
    let trimmed = template?.trim();
    if trimmed.is_empty() || !parts.parsed {
        return None;
    }
    build_mirror(trimmed, original, parts).ok()
}

/// `java.net.URLEncoder` with `+` replaced by `%20`: `A-Z a-z 0-9 - _ . *` pass through, every
/// other UTF-8 byte becomes an uppercase `%XX`.
pub fn encode_java_url_encoder(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.as_bytes() {
        let plain = byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'*');
        if plain {
            out.push(*byte as char);
        } else if *byte == b' ' {
            out.push_str("%20");
        } else {
            out.push('%');
            out.push_str(&format!("{byte:02X}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parts(scheme: &str, host: &str, path: &str, query: &str) -> UrlParts {
        UrlParts {
            parsed: true,
            has_scheme: true,
            scheme: scheme.to_owned(),
            host: host.to_owned(),
            path: path.to_owned(),
            query: query.to_owned(),
        }
    }

    #[test]
    fn encoder_matches_java() {
        assert_eq!(encode_java_url_encoder("a b"), "a%20b");
        assert_eq!(
            encode_java_url_encoder("https://example.com/rules.txt?q=1"),
            "https%3A%2F%2Fexample.com%2Frules.txt%3Fq%3D1"
        );
        assert_eq!(encode_java_url_encoder("-_.*~"), "-_.*%7E");
        assert_eq!(encode_java_url_encoder("中"), "%E4%B8%AD");
    }

    #[test]
    fn replacement_order_is_frozen() {
        // `{url}` is substituted before `{path}`, so a URL containing `{path}` is rewritten again.
        let built = build_mirror(
            "https://m/{url}",
            "https://x/{path}",
            &parts("https", "x", "/a", ""),
        )
        .unwrap();
        assert_eq!(built, "https://m/https://x//a");
    }

    #[test]
    fn template_requires_a_placeholder() {
        assert_eq!(normalize_template(Some("   ")), Ok(None));
        assert_eq!(
            normalize_template(Some("https://m/static")),
            Err(MirrorError::Placeholder)
        );
        assert_eq!(
            normalize_template(Some("ftp://m/{url}")),
            Err(MirrorError::Scheme)
        );
        assert_eq!(
            normalize_template(Some("  https://m/{url}  ")),
            Ok(Some("https://m/{url}".to_owned()))
        );
    }

    #[test]
    fn validation_order() {
        assert_eq!(
            validate(" ", &parts("https", "x", "/", "")),
            Err(UrlError::Empty)
        );
        assert_eq!(
            validate("x", &UrlParts::default()),
            Err(UrlError::BadFormat)
        );
        assert_eq!(
            validate("ftp://x", &parts("ftp", "x", "/", "")),
            Err(UrlError::NotHttp)
        );
        assert_eq!(
            validate("https://", &parts("https", "", "/", "")),
            Err(UrlError::NoHost)
        );
        assert_eq!(validate("https://x", &parts("https", "x", "/", "")), Ok(()));
    }
}

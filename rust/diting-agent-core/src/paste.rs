use regex::Regex;
use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasteKind {
    Empty = 0,
    Json = 1,
    Both = 2,
    BaseUrl = 3,
    Key = 4,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PasteResult {
    pub kind: PasteKind,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub model: Option<String>,
}

impl PasteResult {
    fn new(kind: PasteKind) -> Self {
        Self {
            kind,
            base_url: None,
            api_key: None,
            model: None,
        }
    }
}

fn url_regex() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r#"https?://[^\s,;"'\(\)]+"#).expect("url pattern"))
}

fn key_regex() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(r"(?:sk-[a-zA-Z0-9_\-]{16,}|(?:Bearer\s+)?([a-zA-Z0-9_\-]{32,}))")
            .expect("key pattern")
    })
}

pub fn sanitize(input: &str) -> String {
    let cleaned: String = input
        .chars()
        .filter(|character| !matches!(character, '\r' | '\n' | '\t' | ' '))
        .collect();
    cleaned.trim().to_string()
}

fn replace_first(haystack: &str, needle: &str, replacement: &str) -> String {
    match haystack.find(needle) {
        Some(index) => {
            let mut output = String::with_capacity(haystack.len() + replacement.len());
            output.push_str(&haystack[..index]);
            output.push_str(replacement);
            output.push_str(&haystack[index + needle.len()..]);
            output
        }
        None => haystack.to_string(),
    }
}

fn strip_trailing_slashes(value: &str) -> &str {
    value.trim_end_matches('/')
}

pub fn parse(raw: &str) -> PasteResult {
    let text = raw.trim();
    if text.is_empty() {
        return PasteResult::new(PasteKind::Empty);
    }

    if text.starts_with('{') && text.ends_with('}') {
        if let Some(parsed) = parse_json_config(text) {
            return parsed;
        }
    }

    let found_url = url_regex()
        .find(text)
        .map(|found| strip_trailing_slashes(found.as_str()).to_string());
    let text_without_url = match &found_url {
        Some(url) => replace_first(text, url, ""),
        None => text.to_string(),
    };
    let found_key = key_regex().find(&text_without_url).map(|found| {
        replace_first(found.as_str(), "Bearer ", "")
            .trim()
            .to_string()
    });

    if let (Some(url), Some(key)) = (&found_url, &found_key) {
        if !key.is_empty() {
            return PasteResult {
                kind: PasteKind::Both,
                base_url: Some(sanitize(url)),
                api_key: Some(sanitize(key)),
                model: None,
            };
        }
    }

    if let Some(url) = &found_url {
        let lines = text.matches('\n').count() + 1;
        if lines <= 2 && !text.contains("sk-") {
            return PasteResult {
                kind: PasteKind::BaseUrl,
                base_url: Some(sanitize(url)),
                api_key: None,
                model: None,
            };
        }
    }

    PasteResult {
        kind: PasteKind::Key,
        base_url: None,
        api_key: Some(sanitize(&replace_first(text, "Bearer ", ""))),
        model: None,
    }
}

fn parse_json_config(text: &str) -> Option<PasteResult> {
    let decoded: serde_json::Value = serde_json::from_str(text).ok()?;
    let object = decoded.as_object()?;
    let read = |keys: &[&str]| -> String {
        for key in keys {
            if let Some(serde_json::Value::String(value)) = object.get(*key) {
                if !value.trim().is_empty() {
                    return value.clone();
                }
            }
        }
        String::new()
    };

    let key = read(&["apiKey", "api_key", "key"]);
    let url = read(&["baseUrl", "base_url", "url"]);
    let model = read(&["model"]);
    if key.is_empty() && url.is_empty() && model.is_empty() {
        return None;
    }
    Some(PasteResult {
        kind: PasteKind::Json,
        base_url: (!url.is_empty()).then(|| sanitize(&url)),
        api_key: (!key.is_empty()).then(|| sanitize(&key)),
        model: (!model.is_empty()).then(|| sanitize(&model)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_gives_url_key_and_model() {
        let parsed = parse(
            r#"{"apiKey":"sk-abcdefghijklmnop","baseUrl":"https://api.test/v1","model":"m1"}"#,
        );
        assert_eq!(parsed.kind, PasteKind::Json);
        assert_eq!(parsed.api_key.as_deref(), Some("sk-abcdefghijklmnop"));
        assert_eq!(parsed.base_url.as_deref(), Some("https://api.test/v1"));
        assert_eq!(parsed.model.as_deref(), Some("m1"));
    }

    #[test]
    fn json_alt_keys_and_empty_json() {
        let parsed = parse(r#"{"api_key":"sk-1","url":"https://x.test"}"#);
        assert_eq!(parsed.kind, PasteKind::Json);
        assert_eq!(parsed.api_key.as_deref(), Some("sk-1"));
        assert_eq!(parsed.base_url.as_deref(), Some("https://x.test"));
        assert_eq!(parsed.model, None);

        assert_eq!(parse("{}").kind, PasteKind::Key);
        assert_eq!(parse(r#"{"a":1}"#).kind, PasteKind::Key);
    }

    #[test]
    fn url_and_key_pair_is_split() {
        let parsed = parse("https://api.test/v1, sk-abcdefghijklmnop");
        assert_eq!(parsed.kind, PasteKind::Both);
        assert_eq!(parsed.base_url.as_deref(), Some("https://api.test/v1"));
        assert_eq!(parsed.api_key.as_deref(), Some("sk-abcdefghijklmnop"));
    }

    #[test]
    fn bearer_prefix_is_dropped() {
        let parsed = parse("https://api.test/v1\nBearer sk-abcdefghijklmnop");
        assert_eq!(parsed.kind, PasteKind::Both);
        assert_eq!(parsed.api_key.as_deref(), Some("sk-abcdefghijklmnop"));
    }

    #[test]
    fn bare_url_is_a_base_url() {
        let parsed = parse("https://api.deepseek.com/v1/");
        assert_eq!(parsed.kind, PasteKind::BaseUrl);
        assert_eq!(
            parsed.base_url.as_deref(),
            Some("https://api.deepseek.com/v1")
        );
        assert_eq!(parsed.api_key, None);
    }

    #[test]
    fn bare_key_keeps_newlines_and_spaces_out() {
        let parsed = parse("  sk-abcdefghijklmnop\n ");
        assert_eq!(parsed.kind, PasteKind::Key);
        assert_eq!(parsed.api_key.as_deref(), Some("sk-abcdefghijklmnop"));
        assert_eq!(parsed.base_url, None);
    }

    #[test]
    fn long_url_paste_without_sk_is_a_key() {
        let parsed = parse("https://a.test\nx\n y");
        assert_eq!(parsed.kind, PasteKind::Key);
        assert_eq!(parsed.api_key.as_deref(), Some("https://a.testxy"));
    }

    #[test]
    fn empty_paste_is_reported_as_empty() {
        let parsed = parse("   \n ");
        assert_eq!(parsed.kind, PasteKind::Empty);
        assert_eq!(parsed.api_key, None);
        assert_eq!(parsed.base_url, None);
        assert_eq!(parsed.model, None);
    }

    #[test]
    fn sanitize_drops_inner_whitespace() {
        assert_eq!(sanitize(" a\tb\r\nc "), "abc");
    }
}

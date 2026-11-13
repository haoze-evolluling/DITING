//! Runtime-event policy for the always-on "black box" of the app's own behaviour.
//!
//! The Kotlin `RuntimeEventLog` owns the file, the timestamps and the batching; what moves here is
//! everything that must not drift: the level order, the single-line format, the value escaping and
//! the de-duplication window that keeps a burst of the same warning from flooding the ring.
//!
//! A line reads `2026-01-02 03:04:05.123 INFO service engine.start ok=true mode=normal`; a value is
//! quoted only when it contains whitespace, `"`, `=` or a backslash, so ordinary codes stay short.
//! The format is deliberately the logcat-continuity kind: a human can `grep`/`tail` it and a script
//! can split on the first four fields. It is not JSON because the file is read in a 512 KiB ring.

use std::collections::HashMap;

/// De-duplication table bound; past it the oldest entries are pruned first.
pub const MAX_DEDUP_ENTRIES: usize = 1024;

/// One event file's size budget before the writer rotates to the other slot.
pub const EVENT_MAX_FILE_BYTES: i64 = 512 * 1024;

/// Event files kept (a two-slot ring: `runtime-events.log` + `runtime-events.1.log`).
pub const EVENT_MAX_FILES: usize = 2;

/// Fields one event may carry; the writer drops the excess instead of growing a line without bound.
pub const MAX_FIELDS: usize = 24;

/// Longest single field value kept (in characters); longer text is truncated with an ellipsis.
pub const MAX_FIELD_VALUE_CHARS: usize = 240;

/// Longest module / event / field-name token kept.
pub const MAX_TOKEN_CHARS: usize = 48;

/// Severity order. The numbers are the JNI tags too, so `from_tag` is the wire contract.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default)]
pub enum Level {
    Debug = 0,
    #[default]
    Info = 1,
    Warn = 2,
    Error = 3,
    Fatal = 4,
}

impl Level {
    /// The wire tag; unknown means drift, not a silent default.
    pub fn from_tag(tag: u8) -> Option<Self> {
        match tag {
            0 => Some(Self::Debug),
            1 => Some(Self::Info),
            2 => Some(Self::Warn),
            3 => Some(Self::Error),
            4 => Some(Self::Fatal),
            _ => None,
        }
    }

    pub fn tag(self) -> u8 {
        self as u8
    }

    /// The fixed four/three-letter label a reader greps for.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Debug => "DEBUG",
            Self::Info => "INFO",
            Self::Warn => "WARN",
            Self::Error => "ERROR",
            Self::Fatal => "FATAL",
        }
    }
}

/// `level >= min`, the one comparison the UI's "minimum level" setting means.
pub fn at_least(min: Level, level: Level) -> bool {
    level >= min
}

/// One decoded event, before formatting and the level/dedup gates.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Event {
    /// `yyyy-MM-dd HH:mm:ss.SSS` in the device zone, formatted by Kotlin.
    pub time_text: String,
    pub level: Level,
    pub module: String,
    pub code: String,
    pub fields: Vec<(String, String)>,
}

/// Keeps a short token (`module`, `code`, field name) on one line and within [`MAX_TOKEN_CHARS`].
fn sanitize_token(text: &str) -> String {
    let mut out = String::with_capacity(text.len().min(MAX_TOKEN_CHARS));
    for ch in text.chars() {
        if out.chars().count() >= MAX_TOKEN_CHARS {
            break;
        }
        if ch.is_whitespace() || ch.is_control() || ch == '=' || ch == '"' || ch == '\\' {
            out.push('_');
        } else {
            out.push(ch);
        }
    }
    if out.is_empty() {
        out.push('-');
    }
    out
}

/// Keys whose value must never reach the black box: subscription URLs, proxy credentials, tokens.
/// Matched case-insensitively as `key=value` pairs (URL query or `k=v` prose).
const SENSITIVE_KEYS: &[&str] = &[
    "token",
    "access_token",
    "refresh_token",
    "password",
    "passwd",
    "pwd",
    "secret",
    "api_key",
    "apikey",
    "auth",
    "authorization",
    "subscribe",
    "subscription",
    "session",
    "cookie",
    "sig",
    "signature",
];

fn is_word_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

/// A value ends at a query separator, whitespace or a closing bracket/quote.
fn is_delim(byte: u8) -> bool {
    matches!(
        byte,
        b'&' | b';'
            | b','
            | b' '
            | b'\t'
            | b'\n'
            | b'\r'
            | b'"'
            | b'\''
            | b')'
            | b']'
            | b'}'
            | b'#'
    )
}

/// `Bearer <token>` -> `Bearer ***`.
fn mask_bearer(input: &str) -> String {
    let lower = input.to_ascii_lowercase();
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut index = 0;
    while index < bytes.len() {
        if index + 7 <= bytes.len()
            && &lower[index..index + 6] == "bearer"
            && (index == 0 || !is_word_byte(bytes[index - 1]))
            && bytes[index + 6].is_ascii_whitespace()
        {
            out.push_str(&input[index..index + 6]);
            let mut cursor = index + 6;
            while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
                out.push(' ');
                cursor += 1;
            }
            while cursor < bytes.len()
                && !bytes[cursor].is_ascii_whitespace()
                && !is_delim(bytes[cursor])
            {
                cursor += 1;
            }
            out.push_str("***");
            index = cursor;
            continue;
        }
        let ch = input[index..].chars().next().unwrap();
        out.push(ch);
        index += ch.len_utf8();
    }
    out
}

/// `scheme://user:pass@host/...` -> `scheme://***@host/...`.
fn mask_userinfo(input: &str) -> String {
    let Some(scheme_end) = input.find("://") else {
        return input.to_string();
    };
    let start = scheme_end + 3;
    let rest = &input[start..];
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    let Some(at) = authority.rfind('@') else {
        return input.to_string();
    };
    let mut out = String::with_capacity(input.len());
    out.push_str(&input[..start]);
    out.push_str("***");
    out.push_str(&authority[at..]);
    out.push_str(&rest[authority_end..]);
    out
}

/// `token=abc123`, `password=x`, `sub=...` -> `token=***`, etc., preserving every other byte.
fn mask_key_values(input: &str) -> String {
    let lower = input.to_ascii_lowercase();
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut index = 0;
    while index < bytes.len() {
        let mut matched: Option<usize> = None;
        for key in SENSITIVE_KEYS {
            let length = key.len();
            if index + length < bytes.len()
                && &lower[index..index + length] == *key
                && bytes[index + length] == b'='
                && (index == 0 || !is_word_byte(bytes[index - 1]))
            {
                matched = Some(length);
                break;
            }
        }
        if let Some(length) = matched {
            out.push_str(&input[index..index + length]);
            out.push('=');
            let mut cursor = index + length + 1;
            while cursor < bytes.len() && !is_delim(bytes[cursor]) {
                cursor += 1;
            }
            out.push_str("***");
            index = cursor;
        } else {
            let ch = input[index..].chars().next().unwrap();
            out.push(ch);
            index += ch.len_utf8();
        }
    }
    out
}

/// Masks the three shapes of secret that can leak into an event value: an `Authorization: Bearer`
/// token, URL userinfo, and a sensitive `key=value`. Idempotent and purely textual, so it can run on
/// every value without a regex dependency.
pub fn redact(text: &str) -> String {
    let after_bearer = mask_bearer(text);
    let after_userinfo = mask_userinfo(&after_bearer);
    mask_key_values(&after_userinfo)
}

/// One field value: secret-masked, trimmed of line breaks, truncated, and quoted only when a bare
/// token would misread. A newline inside an exception message becomes a space so the file stays
/// line-oriented.
fn render_value(text: &str) -> String {
    let redacted = redact(text);
    let mut cleaned = String::with_capacity(redacted.len().min(MAX_FIELD_VALUE_CHARS));
    for ch in redacted.chars() {
        if cleaned.chars().count() >= MAX_FIELD_VALUE_CHARS {
            cleaned.push('…');
            break;
        }
        match ch {
            '\n' | '\r' | '\t' => cleaned.push(' '),
            _ => cleaned.push(ch),
        }
    }
    let needs_quote = cleaned.is_empty()
        || cleaned
            .chars()
            .any(|c| c.is_whitespace() || c == '"' || c == '=' || c == '\\');
    if !needs_quote {
        return cleaned;
    }
    let mut quoted = String::with_capacity(cleaned.len() + 2);
    quoted.push('"');
    for ch in cleaned.chars() {
        match ch {
            '"' => quoted.push_str("\\\""),
            '\\' => quoted.push_str("\\\\"),
            _ => quoted.push(ch),
        }
    }
    quoted.push('"');
    quoted
}

/// The one-line rendering of [`Event`]. `time_text` is passed through (Kotlin formats it) but kept
/// on one line so a bad timestamp cannot split a record.
pub fn format_event(event: &Event) -> String {
    let time: String = event
        .time_text
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect();
    let mut line = String::with_capacity(96);
    line.push_str(time.trim());
    line.push(' ');
    line.push_str(event.level.as_str());
    line.push(' ');
    line.push_str(&sanitize_token(&event.module));
    line.push(' ');
    line.push_str(&sanitize_token(&event.code));
    for (key, value) in event.fields.iter().take(MAX_FIELDS) {
        line.push(' ');
        line.push_str(&sanitize_token(key));
        line.push('=');
        line.push_str(&render_value(value));
    }
    line
}

/// De-duplication key: module + code + every field, never the timestamp.
fn dedup_key(event: &Event) -> String {
    let mut key = String::with_capacity(64);
    key.push_str(&event.module);
    key.push('\u{1f}');
    key.push_str(&event.code);
    for (name, value) in &event.fields {
        key.push('\u{1f}');
        key.push_str(name);
        key.push('=');
        key.push_str(value);
    }
    key
}

/// Stateful gate: the minimum level plus the "same event within N ms" suppressor.
///
/// Kotlin keeps exactly one gate per process. A `dedup_window_ms` of 0 disables de-duplication
/// (every admitted event is written); a positive window writes the first of a burst and swallows
/// the repeats, so a retry storm costs one line, not thousands.
#[derive(Debug)]
pub struct Gate {
    min_level: Level,
    dedup_window_ms: i64,
    last_seen: HashMap<String, i64>,
}

impl Gate {
    pub fn new(min_level: Level, dedup_window_ms: i64) -> Self {
        Self {
            min_level,
            dedup_window_ms: dedup_window_ms.max(0),
            last_seen: HashMap::new(),
        }
    }

    pub fn min_level(&self) -> Level {
        self.min_level
    }

    pub fn set_min_level(&mut self, level: Level) {
        self.min_level = level;
    }

    /// `Some(line)` when the event should be written; `None` when the level filtered it or a repeat
    /// fell inside the window.
    pub fn admit(&mut self, event: &Event, now_ms: i64) -> Option<String> {
        if !at_least(self.min_level, event.level) {
            return None;
        }
        if self.dedup_window_ms > 0 {
            let key = dedup_key(event);
            if let Some(&last) = self.last_seen.get(&key) {
                if now_ms.saturating_sub(last) < self.dedup_window_ms {
                    // Refresh the window so a continuous stream stays suppressed, not re-fires.
                    self.last_seen.insert(key, now_ms);
                    return None;
                }
            }
            self.last_seen.insert(key, now_ms);
            self.prune(now_ms);
        }
        Some(format_event(event))
    }

    /// Drops entries older than twice the window, then (if still over the bound) the oldest ones.
    fn prune(&mut self, now_ms: i64) {
        if self.last_seen.len() <= MAX_DEDUP_ENTRIES {
            return;
        }
        let horizon = self.dedup_window_ms.saturating_mul(2);
        self.last_seen
            .retain(|_, seen| now_ms.saturating_sub(*seen) < horizon);
        if self.last_seen.len() <= MAX_DEDUP_ENTRIES {
            return;
        }
        let mut by_age: Vec<(String, i64)> = self
            .last_seen
            .iter()
            .map(|(key, seen)| (key.clone(), *seen))
            .collect();
        by_age.sort_by_key(|(_, seen)| *seen);
        let excess = by_age.len().saturating_sub(MAX_DEDUP_ENTRIES);
        for (key, _) in by_age.into_iter().take(excess) {
            self.last_seen.remove(&key);
        }
    }
}

impl Default for Gate {
    fn default() -> Self {
        Self::new(Level::Info, 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(level: Level, module: &str, code: &str) -> Event {
        Event {
            time_text: "2026-01-02 03:04:05.123".into(),
            level,
            module: module.into(),
            code: code.into(),
            fields: Vec::new(),
        }
    }

    #[test]
    fn levels_round_trip_and_order() {
        for tag in 0u8..=4 {
            let level = Level::from_tag(tag).unwrap();
            assert_eq!(level.tag(), tag);
        }
        assert_eq!(Level::from_tag(5), None);
        assert!(at_least(Level::Info, Level::Warn));
        assert!(!at_least(Level::Warn, Level::Info));
    }

    #[test]
    fn a_line_carries_time_level_module_code_and_fields() {
        let mut ev = event(Level::Warn, "service", "engine.start");
        ev.fields.push(("mode".into(), "normal".into()));
        ev.fields.push(("error".into(), "connect timeout".into()));
        assert_eq!(
            format_event(&ev),
            "2026-01-02 03:04:05.123 WARN service engine.start mode=normal error=\"connect timeout\""
        );
    }

    #[test]
    fn a_value_with_quotes_equals_or_newlines_is_escaped_on_one_line() {
        let mut ev = event(Level::Error, "db", "open.fail");
        ev.fields
            .push(("cause".into(), "bad \"x\"=1\\2\nnext line".into()));
        let line = format_event(&ev);
        assert!(!line.contains('\n'), "a record stays one line: {line}");
        assert!(
            line.contains("cause=\"bad \\\"x\\\"=1\\\\2 next line\""),
            "{line}"
        );
    }

    #[test]
    fn over_long_values_are_truncated_with_an_ellipsis() {
        let mut ev = event(Level::Info, "x", "y");
        ev.fields
            .push(("big".into(), "z".repeat(MAX_FIELD_VALUE_CHARS + 50)));
        let line = format_event(&ev);
        assert!(line.ends_with('…'));
        assert!(line.chars().count() < MAX_FIELD_VALUE_CHARS + 80);
    }

    #[test]
    fn the_minimum_level_filters_before_the_dedup_table() {
        let mut gate = Gate::new(Level::Warn, 5_000);
        assert_eq!(gate.admit(&event(Level::Info, "a", "b"), 0), None);
        assert!(gate.admit(&event(Level::Warn, "a", "b"), 0).is_some());
    }

    #[test]
    fn repeats_inside_the_window_are_suppressed_and_resurface_after_it() {
        let mut gate = Gate::new(Level::Debug, 5_000);
        let ev = event(Level::Info, "net", "dial.fail");
        assert!(gate.admit(&ev, 1_000).is_some());
        assert_eq!(gate.admit(&ev, 2_000), None);
        assert_eq!(gate.admit(&ev, 5_999), None);
        // A suppressed repeat refreshes the window, so a continuous stream keeps one line.
        assert_eq!(gate.admit(&ev, 6_000), None);
        // A full window of silence lets the next occurrence through again.
        assert!(gate.admit(&ev, 11_000).is_some());
    }

    #[test]
    fn a_zero_window_disables_dedup() {
        let mut gate = Gate::new(Level::Debug, 0);
        let ev = event(Level::Info, "net", "dial.fail");
        assert!(gate.admit(&ev, 1_000).is_some());
        assert!(gate.admit(&ev, 1_000).is_some());
    }

    #[test]
    fn the_dedup_table_is_pruned_to_its_bound() {
        let mut gate = Gate::new(Level::Debug, 1_000);
        for index in 0..(MAX_DEDUP_ENTRIES + 200) {
            let mut ev = event(Level::Info, "m", "c");
            ev.fields.push(("i".into(), index.to_string()));
            assert!(gate.admit(&ev, index as i64).is_some());
        }
        assert!(gate.last_seen.len() <= MAX_DEDUP_ENTRIES);
    }

    #[test]
    fn redaction_masks_url_userinfo_and_sensitive_query_values() {
        let raw = "https://user:p@ssw0rd!@example.com/path?token=s3cr3t-abc&x=1";
        let masked = redact(raw);
        assert!(
            masked.starts_with("https://***@example.com/path"),
            "{masked}"
        );
        assert!(masked.contains("token=***"), "{masked}");
        assert!(masked.contains("x=1"), "{masked}");
        assert!(!masked.contains("s3cr3t"), "{masked}");
        assert!(!masked.contains("p@ssw0rd"), "{masked}");
    }

    #[test]
    fn redaction_masks_a_bearer_token_and_bare_kv_secrets() {
        assert_eq!(redact("Bearer abc.def-ghi"), "Bearer ***");
        assert_eq!(
            redact("password=hunter2 host=1.1.1.1"),
            "password=*** host=1.1.1.1"
        );
        // The key has to be a whole word: `apikeyx` is not `apikey`.
        assert_eq!(redact("apikeyx=keep"), "apikeyx=keep");
    }

    #[test]
    fn redaction_leaves_ordinary_text_alone_and_is_idempotent() {
        assert_eq!(
            redact("connect timeout after 3s"),
            "connect timeout after 3s"
        );
        let once = redact("https://u:p@h/p?sub=xyz");
        assert_eq!(redact(&once), once);
    }

    #[test]
    fn format_event_masks_a_secret_field_value() {
        let mut ev = event(Level::Warn, "sub", "refresh.fail");
        ev.fields.push((
            "url".into(),
            "https://api.example.com/sub?token=abc123".into(),
        ));
        let line = format_event(&ev);
        assert!(line.contains("token=***"), "{line}");
        assert!(!line.contains("abc123"), "{line}");
    }
}

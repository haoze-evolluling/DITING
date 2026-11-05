//! Go `regexp` -> Rust `regex` translation for user rule patterns.
//!
//! Both engines are RE2 descendants, so most of the syntax carries over unchanged. The shorthands
//! are the exception: Go's `\d`, `\w`, `\s` and `\b` are **ASCII only**, while the Rust crate makes
//! them Unicode aware by default. Rules match lowercased DNS names, where the difference only shows
//! up for non-ASCII digits/letters, but translating them keeps the two engines identical for ASCII
//! input instead of relying on that.
//!
//! Unsupported constructs (`(?U)`, `\p{^Greek}`, ...) are translated where it is mechanical and
//! otherwise left alone: a pattern that then fails to compile is caught by the build-time status
//! check in [`crate::ffi`] (Go compiled it, Rust did not), and the whole snapshot falls back to the
//! Go engine. Known, documented differences are listed in `rust/README.md`.

use regex::Regex;

/// `\d` and friends, expansion outside / inside a character class.
const ASCII_DIGIT: &str = "[0-9]";
const ASCII_WORD: &str = "[0-9A-Za-z_]";
const ASCII_SPACE: &str = "[\\t\\n\\f\\r ]";

/// Translates one Go regular expression into the closest Rust equivalent.
pub fn translate(pattern: &str) -> String {
    let mut out = String::with_capacity(pattern.len() + 8);
    let mut chars = pattern.chars().peekable();
    let mut in_class = false;
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                let Some(next) = chars.next() else {
                    out.push('\\');
                    break;
                };
                match next {
                    'd' => out.push_str(if in_class { "0-9" } else { ASCII_DIGIT }),
                    'D' => out.push_str(if in_class { "\\D" } else { "[^0-9]" }),
                    'w' => out.push_str(if in_class { "0-9A-Za-z_" } else { ASCII_WORD }),
                    'W' => out.push_str(if in_class { "\\W" } else { "[^0-9A-Za-z_]" }),
                    's' => out.push_str(if in_class {
                        "\\t\\n\\f\\r "
                    } else {
                        ASCII_SPACE
                    }),
                    'S' => out.push_str(if in_class { "\\S" } else { "[^\\t\\n\\f\\r ]" }),
                    'b' => out.push_str(if in_class { "\\x08" } else { "(?-u:\\b)" }),
                    'p' | 'P' => {
                        if chars.peek() == Some(&'{') {
                            // `\p{...}` is spelled the same, except Go's negated form
                            // `\p{^Greek}`, which the Rust engine spells `\P{Greek}`.
                            chars.next();
                            if next == 'p' && chars.peek() == Some(&'^') {
                                chars.next();
                                out.push_str("\\P{");
                            } else {
                                out.push('\\');
                                out.push(next);
                                out.push('{');
                            }
                            continue;
                        }
                        // `\pL` is accepted by Go, the Rust engine wants `\p{L}`.
                        let Some(name) = chars.next() else {
                            out.push('\\');
                            out.push(next);
                            continue;
                        };
                        out.push('\\');
                        out.push(next);
                        out.push('{');
                        out.push(name);
                        out.push('}');
                    }
                    other => {
                        out.push('\\');
                        out.push(other);
                    }
                }
            }
            '[' if !in_class => {
                in_class = true;
                out.push('[');
                if chars.peek() == Some(&'^') {
                    out.push(chars.next().unwrap_or('^'));
                }
                if chars.peek() == Some(&']') {
                    out.push(chars.next().unwrap_or(']'));
                }
            }
            ']' if in_class => {
                in_class = false;
                out.push(']');
            }
            other => out.push(other),
        }
    }
    out
}

/// True when a `|` appears at the top level of the pattern, which makes any literal prefix
/// optional (`^a|^b`) and therefore unusable as a prefilter.
fn top_level_alternation(pattern: &str) -> bool {
    let mut depth = 0i32;
    let mut in_class = false;
    let mut escaped = false;
    for c in pattern.chars() {
        if escaped {
            escaped = false;
            continue;
        }
        match c {
            '\\' => escaped = true,
            '[' if !in_class => in_class = true,
            ']' if in_class => in_class = false,
            '(' if !in_class => depth += 1,
            ')' if !in_class => depth -= 1,
            '|' if !in_class && depth == 0 => return true,
            _ => {}
        }
    }
    false
}

/// `regexAnchoredPrefix`: the ASCII literal every match of an anchored pattern must start with.
///
/// Go derives it with `regexp/syntax` + `Simplify`; this is the string-level equivalent for the
/// shapes rules use (`^literal...`), and it is deliberately conservative: whenever the shape is not
/// obvious the answer is "no prefix", which only costs the prefilter, never a match.
pub fn anchored_prefix(pattern: &str) -> String {
    if top_level_alternation(pattern) {
        return String::new();
    }
    let mut rest = pattern;
    while let Some(stripped) = rest.strip_prefix("(?") {
        let Some(close) = stripped.find(')') else {
            return String::new();
        };
        let flags = &stripped[..close];
        // `(?i:...)`/`(?:...)` are groups, not flags: give up rather than guess.
        if flags.is_empty() || !flags.bytes().all(|b| b.is_ascii_alphabetic() || b == b'-') {
            return String::new();
        }
        rest = &stripped[close + 1..];
    }
    let Some(rest) = rest.strip_prefix('^') else {
        return String::new();
    };
    let mut prefix = String::new();
    let mut chars = rest.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                let Some(next) = chars.next() else { break };
                if next.is_ascii_alphanumeric() {
                    // A shorthand or a hex escape: the collected prefix stays, it just cannot be
                    // extended past this point.
                    return crate::text::go_lower(&prefix).into_owned();
                }
                prefix.push(next);
            }
            '*' | '+' | '?' | '{' => {
                // The quantifier applies to the last collected character, which is therefore not
                // part of the required prefix (`^ab?c` only requires `a`).
                prefix.pop();
                return crate::text::go_lower(&prefix).into_owned();
            }
            '.' | '(' | ')' | '[' | ']' | '}' | '|' | '^' | '$' => {
                return crate::text::go_lower(&prefix).into_owned();
            }
            c if !c.is_ascii() => return crate::text::go_lower(&prefix).into_owned(),
            c => prefix.push(c),
        }
    }
    crate::text::go_lower(&prefix).into_owned()
}

/// `mayMatchPrefix`: non-ASCII domains are never rejected because `(?i)` folds more than ASCII.
pub fn may_match_prefix(domain: &str, prefix: &str) -> bool {
    if prefix.is_empty() || !domain.is_ascii() {
        return true;
    }
    domain.len() >= prefix.len()
        && domain.as_bytes()[..prefix.len()].eq_ignore_ascii_case(prefix.as_bytes())
}

/// Compiles one rule pattern the way `parseSpecialRule` does: an `(?i)` prefix unless the pattern
/// already carries one, then the translation above.
pub fn compile_rule_regex(pattern: &str) -> Result<Regex, String> {
    let prefixed = if crate::text::has_fold_prefix(pattern) {
        pattern.to_string()
    } else {
        format!("(?i){pattern}")
    };
    Regex::new(&translate(&prefixed)).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn matches(pattern: &str, domain: &str) -> bool {
        compile_rule_regex(pattern)
            .unwrap_or_else(|error| panic!("{pattern}: {error}"))
            .is_match(domain)
    }

    #[test]
    fn plain_patterns_are_unchanged() {
        assert_eq!(translate("^ads\\.example\\.com$"), "^ads\\.example\\.com$");
        assert!(matches("^ad[s0-9]*\\.test\\.com$", "ad123.test.com"));
        assert!(!matches("^ad[s0-9]*\\.test\\.com$", "not-ads.test.com"));
    }

    #[test]
    fn shorthands_become_ascii() {
        assert_eq!(translate("\\d+"), "[0-9]+");
        assert_eq!(translate("[\\d]+"), "[0-9]+");
        assert_eq!(translate("\\s"), "[\\t\\n\\f\\r ]");
        assert_eq!(translate("[\\s]"), "[\\t\\n\\f\\r ]");
        assert_eq!(translate("\\w"), "[0-9A-Za-z_]");
        assert_eq!(translate("\\bads\\b"), "(?-u:\\b)ads(?-u:\\b)");
        assert_eq!(translate("[\\b]"), "[\\x08]");
    }

    #[test]
    fn ascii_shorthands_really_are_ascii() {
        // U+0661 ARABIC-INDIC DIGIT ONE is a Unicode digit; Go's `\d` is [0-9].
        assert!(!matches("^\\d+$", "\u{0661}"));
        // U+017F LATIN SMALL LETTER LONG S folds to `s` in both engines.
        assert!(matches("^s+$", "\u{017F}"));
    }

    #[test]
    fn unicode_classes_and_brace_forms() {
        assert_eq!(translate("\\pL"), "\\p{L}");
        assert_eq!(translate("\\P{Greek}"), "\\P{Greek}");
        assert_eq!(translate("\\p{^Greek}"), "\\P{Greek}");
        assert!(!translate("\\p{^Greek}").contains("p{^"));
    }

    #[test]
    fn classes_with_brackets_and_carets_survive() {
        assert_eq!(translate("[]a]"), "[]a]");
        assert_eq!(translate("[^]a]"), "[^]a]");
        assert!(matches("^[]a]+$", "]a"));
        assert!(matches("^[^]a]+$", "bcd"));
    }

    #[test]
    fn anchored_prefix_matches_the_go_reference_cases() {
        // Same expectations as TestRegexAnchoredPrefixAgreesWithRegex in the Go engine.
        let cases = [
            (r"(?i)^banner7\..*\.cn$", "banner7."),
            (r"(?i)^ad[0-9]+\.", "ad"),
            (r"(?i)ads\.", ""),
            (r"(?i)^(ads|track)\.", ""),
            (r"(?i)^a|^b", ""),
            (r"(?i)^ab?c", "a"),
        ];
        for (pattern, want) in cases {
            assert_eq!(anchored_prefix(pattern), want, "{pattern}");
        }
    }

    #[test]
    fn anchored_prefix_never_rejects_a_real_match() {
        let patterns = [
            r"(?i)^banner7\..*\.cn$",
            r"(?i)^ad[0-9]+\.",
            r"^ads\.example\.com$",
            r"(?is)^a.b",
            r"^a{2}b",
            r"^x\\y",
        ];
        let domains = [
            "banner7.x.cn",
            "banner7x.cn",
            "ad12.com",
            "ads.example.com",
            "a\nb",
            "aab",
            "x\\y",
            "zzz.example",
            "ads.example.com.",
        ];
        for pattern in patterns {
            let regex =
                compile_rule_regex(pattern).unwrap_or_else(|error| panic!("{pattern}: {error}"));
            let prefix = anchored_prefix(&format!("(?i){pattern}"));
            for domain in domains {
                if regex.is_match(domain) && !may_match_prefix(domain, &prefix) {
                    panic!("prefix {prefix:?} rejected {domain:?} for {pattern:?}");
                }
            }
        }
    }

    #[test]
    fn inline_flags_are_kept() {
        assert!(matches("(?i)^ADS\\.com$", "ads.com"));
        assert!(matches("(?s)^a.b$", "a\nb"));
    }
}

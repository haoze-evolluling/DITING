//! Single-line rule parsing: cosmetic, URL, modifier and domain forms. A port of
//! `adblock_line_parser.dart`; the dedupe keys live in [`crate::keys`] and the `$modifier` handling
//! in [`crate::modifiers`].
//!
//! The check order is semantic and must not be reordered: cosmetic delimiters before comments,
//! regex/URL forms before the domain fallback, and `$badfilter` keys after the modifiers.
//!
//! Indices are byte-based. Every delimiter this parser slices on is ASCII, so byte offsets stay
//! char boundaries; the only place UTF-16 units decide anything (the comment-scan guard) goes
//! through [`crate::domain::utf16_len`] to stay identical to Dart's `String.length`.

use crate::domain::{normalize_domain, normalize_wildcard_domain, utf16_len};
use crate::keys::{rule_key, url_key};
use crate::models::{
    CategorizedLine, ParsedCosmeticRule, ParsedRewriteRule, ParsedRule, ParsedUrlRule,
};
use crate::modifiers::{apply_modifiers, is_valid_regex, ModifierRejection, ModifierState};

/// Element-hiding delimiters, longest first: `#$@#` is the exception form of `#$#`, so the short
/// one first would demote the rule.
const COSMETIC_DELIMITERS: [&str; 5] = ["#$@#", "#@#", "##", "#?#", "#$#"];

/// Whether the line uses an element-hiding delimiter. Must run before comment filtering: a `#`
/// line may be a comment or a rule.
pub fn is_cosmetic_rule_line(line: &str) -> bool {
    COSMETIC_DELIMITERS
        .iter()
        .any(|delimiter| line.contains(delimiter))
}

/// Index where a trailing `#` comment may start, or 0. A regex may contain `#` (`/foo#bar/`), so
/// the scan starts after the closing `/`.
fn comment_search_start(line: &str, allow: bool) -> usize {
    let offset = if allow && line.starts_with("@@") {
        2
    } else {
        0
    };
    if utf16_len(line) <= offset + 1 || !line.as_bytes()[offset..].starts_with(b"/") {
        return 0;
    }
    let rest = &line[offset + 1..];
    let token_len = rest
        .char_indices()
        .find(|(_, c)| c.is_whitespace())
        .map_or(rest.len(), |(index, _)| index);
    let token_end = offset + 1 + token_len;
    match line[..token_end].rfind('/') {
        Some(closing) if closing > offset => closing + 1,
        _ => 0,
    }
}

/// Case-insensitive ASCII prefix test that allocates nothing: `is_url_or_path_rule` runs for every
/// line that reaches the domain branch, so a `to_ascii_lowercase()` there would be one string
/// allocation per imported line.
fn starts_with_ignore_ascii_case(value: &str, prefix: &str) -> bool {
    value.len() >= prefix.len()
        && value.as_bytes()[..prefix.len()].eq_ignore_ascii_case(prefix.as_bytes())
}

fn is_url_or_path_rule(value: &str) -> bool {
    if starts_with_ignore_ascii_case(value, "http://")
        || starts_with_ignore_ascii_case(value, "https://")
    {
        return true;
    }
    if starts_with_ignore_ascii_case(value, "|http://")
        || starts_with_ignore_ascii_case(value, "|https://")
    {
        return true;
    }
    if let Some(rest) = value.strip_prefix("||") {
        if rest.contains('/') {
            return true;
        }
    }
    if value.starts_with("*/") && utf16_len(value) > 2 {
        return true;
    }
    if value.starts_with('/') && !value.ends_with('/') && utf16_len(value) > 2 {
        return true;
    }
    false
}

fn clean_url_pattern(value: &str) -> String {
    let without_domain_marker = value.strip_prefix("||").unwrap_or(value);
    let without_anchor = without_domain_marker
        .strip_prefix('|')
        .unwrap_or(without_domain_marker);
    without_anchor.trim_end_matches('^').trim().to_string()
}

fn parse_cosmetic_line(line: &str, original: &str) -> Option<CategorizedLine> {
    let is_exception = line.contains("#@#") || line.contains("#$@#");
    let delimiter = *COSMETIC_DELIMITERS
        .iter()
        .find(|delimiter| line.contains(*delimiter))?;
    let index = line.find(delimiter)?;
    let domain_part = line[..index].trim();
    let selector_part = line[index + delimiter.len()..].trim();
    if selector_part.is_empty() {
        return Some(CategorizedLine::invalid());
    }
    let domains: Vec<&str> = if domain_part.is_empty() {
        vec![""]
    } else {
        domain_part
            .split(',')
            .map(str::trim)
            .filter(|domain| !domain.is_empty())
            .collect()
    };
    if domains.is_empty() {
        return Some(CategorizedLine::invalid());
    }
    Some(CategorizedLine {
        cosmetic_rules: domains
            .into_iter()
            .map(|domain| ParsedCosmeticRule {
                domain: domain.to_string(),
                selector: selector_part.to_string(),
                raw_line: original.to_string(),
                is_exception,
            })
            .collect(),
        ..CategorizedLine::default()
    })
}

pub fn parse_line_without_state(line: &str, original: &str, allow: bool) -> CategorizedLine {
    if let Some(cosmetic) = parse_cosmetic_line(line, original) {
        return cosmetic;
    }

    // Only a `#` that starts a trailing comment may be dropped: truncating at a `#` glued to the
    // pattern would widen the rule to a whole domain block.
    let search_start = comment_search_start(line, allow);
    let hash_index = line[search_start..]
        .find('#')
        .map(|index| index + search_start);
    let mut value: &str = match hash_index {
        None => line.trim(),
        Some(index) => {
            let before = &line[..index];
            let ends_with_space = before.chars().next_back().is_none_or(char::is_whitespace);
            if !ends_with_space {
                return CategorizedLine::unsupported();
            }
            before.trim()
        }
    };
    if value.is_empty() {
        return CategorizedLine::invalid();
    }
    if allow {
        value = value.strip_prefix("@@").unwrap_or(value);
    }

    let mut is_regex = false;
    let mut regex_pattern = "";
    let mut modifier_spec: Option<&str> = None;

    if value.starts_with('/') {
        let Some(last_slash) = value.rfind('/').filter(|index| *index > 0) else {
            return CategorizedLine::invalid();
        };
        let extracted = value[1..last_slash].trim();
        if extracted.is_empty() || !is_valid_regex(extracted) {
            return CategorizedLine::invalid();
        }
        is_regex = true;
        regex_pattern = extracted;
        let tail = value[last_slash + 1..].trim();
        if !tail.is_empty() {
            match tail.strip_prefix('$') {
                Some(spec) => modifier_spec = Some(spec),
                None => return CategorizedLine::invalid(),
            }
        }
        value = "";
    }

    if !is_regex {
        if let Some(index) = value.find('$') {
            modifier_spec = Some(&value[index + 1..]);
            value = value[..index].trim();
        }
    }

    let mut state = ModifierState::default();
    if let Some(spec) = modifier_spec.filter(|spec| !spec.is_empty()) {
        if let Err(rejection) = apply_modifiers(spec, &mut state) {
            return match rejection {
                ModifierRejection::Invalid => CategorizedLine::invalid(),
                ModifierRejection::Unsupported => CategorizedLine::unsupported(),
                ModifierRejection::Ignored => CategorizedLine::ignored(),
            };
        }
    }
    // A content-type/party modifier was dropped to keep the host rule (a coverage win for block
    // rules). For an allow rule the same widening would loosen blocking, so still ignore it.
    if state.demoted && allow {
        return CategorizedLine::ignored();
    }

    if !is_regex && is_url_or_path_rule(value) {
        let clean_pattern = clean_url_pattern(value);
        if !clean_pattern.is_empty() {
            if state.is_badfilter {
                let prefix = if allow { "url_allow" } else { "url_block" };
                let mut line = CategorizedLine::default();
                line.badfilter_keys.insert(url_key(
                    prefix,
                    &clean_pattern,
                    state.app_scope.as_deref(),
                ));
                return line;
            }
            let url_rule = ParsedUrlRule {
                pattern: clean_pattern,
                raw_line: original.to_string(),
                is_allow: allow,
                app_scope: state.app_scope.clone(),
                important: state.important,
            };
            return if allow {
                CategorizedLine {
                    url_allow_rules: vec![url_rule],
                    ..CategorizedLine::default()
                }
            } else {
                CategorizedLine {
                    url_block_rules: vec![url_rule],
                    ..CategorizedLine::default()
                }
            };
        }
    }

    let (domain, is_wildcard) = if is_regex {
        (regex_pattern.to_string(), false)
    } else {
        let mut candidate = value;
        if let Some(rest) = candidate.strip_prefix("||") {
            candidate = rest.trim_end_matches('^');
        } else if candidate.starts_with('|') || candidate.ends_with('|') {
            // A single-`|` ABP anchor on a bare host (`|host|`, `|host`, `host|`) is still a
            // host-level rule; strip the anchors and keep the host. A remaining `/` means it is
            // really a URL rule, which stays unsupported here.
            let anchored = candidate
                .trim_start_matches('|')
                .trim_end_matches(|c| c == '|' || c == '^')
                .trim();
            if anchored.is_empty() || anchored.contains('/') {
                return CategorizedLine::unsupported();
            }
            candidate = anchored;
        } else {
            candidate = candidate.trim_end_matches('^');
        }
        let is_wildcard = candidate.contains('*');
        let normalized = if is_wildcard {
            normalize_wildcard_domain(candidate)
        } else {
            normalize_domain(candidate)
        };
        match normalized {
            Some(normalized) => (normalized, is_wildcard),
            None => return CategorizedLine::invalid(),
        }
    };

    let app_scope = state.app_scope.as_deref();
    let denyallow = state.denyallow.as_deref();
    let dns_type = state.dns_type.as_deref();

    if state.is_badfilter {
        let key = match (state.rewrite_type, state.rewrite_value.as_deref()) {
            (Some(target_type), Some(target_value)) => {
                format!("rewrite:{domain}:{target_type}:{target_value}")
            }
            _ => rule_key(
                if state.rewrite_is_block || !allow {
                    "block"
                } else {
                    "allow"
                },
                &domain,
                state.important,
                app_scope,
                state.app_inverted,
                denyallow,
                is_regex,
                dns_type,
            ),
        };
        let mut line = CategorizedLine::default();
        line.badfilter_keys.insert(key);
        return line;
    }

    if let (Some(target_type), Some(target_value)) =
        (state.rewrite_type, state.rewrite_value.clone())
    {
        return CategorizedLine {
            rewrite_rules: vec![ParsedRewriteRule {
                pattern: domain,
                target_type: target_type.to_string(),
                target_value,
                raw_line: original.to_string(),
            }],
            ..CategorizedLine::default()
        };
    }

    let rule = ParsedRule {
        pattern: domain,
        raw_line: original.to_string(),
        important: state.important,
        app_scope: state.app_scope,
        app_inverted: state.app_inverted,
        is_wildcard,
        denyallow: state.denyallow,
        is_regex,
        dns_type: state.dns_type,
    };
    if state.rewrite_is_block {
        return CategorizedLine {
            block_rules: vec![rule],
            ..CategorizedLine::default()
        };
    }
    if allow {
        CategorizedLine {
            allow_rules: vec![rule],
            ..CategorizedLine::default()
        }
    } else {
        CategorizedLine {
            block_rules: vec![rule],
            ..CategorizedLine::default()
        }
    }
}

#[cfg(test)]
mod coverage_tests {
    use super::parse_line_without_state;

    fn block(line: &str) -> crate::models::CategorizedLine {
        parse_line_without_state(line, line, false)
    }

    #[test]
    fn content_type_modifier_keeps_host_block() {
        let parsed = block("||ads.example^$script,image");
        assert_eq!(parsed.block_rules.len(), 1);
        assert_eq!(parsed.block_rules[0].pattern, "ads.example");
        assert!(parsed.allow_rules.is_empty());
    }

    #[test]
    fn referrer_modifier_is_still_dropped() {
        // `$domain=` narrows by referrer; ignoring it would change meaning, so the line stays ignored.
        let parsed = block("||ads.example^$domain=foo.com");
        assert!(parsed.block_rules.is_empty());
        assert!(parsed.allow_rules.is_empty());
    }

    #[test]
    fn allow_rule_with_content_type_modifier_is_dropped() {
        let line = "@@||cdn.example^$script";
        let parsed = parse_line_without_state(line, line, true);
        assert!(parsed.allow_rules.is_empty());
        assert!(parsed.block_rules.is_empty());
    }

    #[test]
    fn single_pipe_anchor_is_a_host_rule() {
        assert_eq!(block("|ads.example|").block_rules[0].pattern, "ads.example");
        assert_eq!(block("ads.example|").block_rules[0].pattern, "ads.example");
        assert_eq!(block("|ads.example").block_rules[0].pattern, "ads.example");
    }

    #[test]
    fn single_pipe_url_anchor_stays_unsupported() {
        assert!(block("|ads.example/path").block_rules.is_empty());
    }
}

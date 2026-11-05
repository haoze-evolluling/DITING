//! `$modifier` handling for one rule line, plus the conservative regex syntax check.
//!
//! The token order below is the order the Dart parser tests them in; a token that is not recognised
//! makes the whole line unsupported, so this order is semantic.

use crate::domain::{
    is_sinkhole, is_valid_dns_type, is_web_only_modifier, looks_like_literal_ip, normalize_domain,
    parse_numeric_address_safe,
};
use crate::models::{REWRITE_CNAME, REWRITE_IPV4, REWRITE_IPV6};

#[derive(Default)]
pub(crate) struct ModifierState {
    pub(crate) important: bool,
    pub(crate) app_scope: Option<String>,
    pub(crate) app_inverted: bool,
    pub(crate) rewrite_type: Option<&'static str>,
    pub(crate) rewrite_value: Option<String>,
    pub(crate) rewrite_is_block: bool,
    pub(crate) is_badfilter: bool,
    pub(crate) denyallow: Option<String>,
    pub(crate) dns_type: Option<String>,
}

enum ModifierOutcome {
    Accepted,
    Invalid,
    Unsupported,
}

/// Which `CategorizedLine` the caller must return when a token is rejected. Kept separate from
/// `CategorizedLine` so the error path stays small.
pub(crate) enum ModifierRejection {
    Invalid,
    Unsupported,
    Ignored,
}

/// `dnsrewrite=a;b;c` takes the last part; a leading NXDOMAIN/REFUSED/SERVFAIL means a blackhole.
fn dnsrewrite_last_part(raw_spec: &str) -> String {
    let parts: Vec<&str> = raw_spec
        .split(';')
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect();
    let Some(last) = parts.last() else {
        return raw_spec.to_string();
    };
    let first = parts[0].to_uppercase();
    if first == "NXDOMAIN" || first == "REFUSED" || first == "SERVFAIL" {
        return "NXDOMAIN".to_string();
    }
    (*last).to_string()
}

fn apply_app_scope(
    token: &str,
    is_negative_prefix: bool,
    state: &mut ModifierState,
) -> ModifierOutcome {
    let app_value = if is_negative_prefix {
        token[5..].trim()
    } else {
        token[4..].trim()
    };
    if app_value.is_empty() {
        return ModifierOutcome::Unsupported;
    }
    let pkgs: Vec<&str> = app_value
        .split('|')
        .map(str::trim)
        .filter(|pkg| !pkg.is_empty())
        .collect();
    if pkgs.is_empty() {
        return ModifierOutcome::Unsupported;
    }
    let has_inverted = is_negative_prefix || pkgs.iter().any(|pkg| pkg.starts_with('~'));
    let clean: Vec<String> = pkgs
        .iter()
        .map(|pkg| pkg.strip_prefix('~').unwrap_or(pkg).trim().to_lowercase())
        .filter(|pkg| !pkg.is_empty())
        .collect();
    if clean.is_empty() {
        return ModifierOutcome::Unsupported;
    }
    state.app_inverted = has_inverted;
    state.app_scope = Some(clean.join("|"));
    ModifierOutcome::Accepted
}

fn apply_denyallow(token: &str, state: &mut ModifierState) -> ModifierOutcome {
    let raw_spec = token[10..].trim();
    if raw_spec.is_empty() {
        return ModifierOutcome::Invalid;
    }
    let raw_domains: Vec<String> = raw_spec
        .split('|')
        .map(|domain| domain.trim().to_lowercase())
        .filter(|domain| !domain.is_empty())
        .collect();
    if raw_domains.is_empty() {
        return ModifierOutcome::Invalid;
    }
    let mut clean = Vec::with_capacity(raw_domains.len());
    for domain in &raw_domains {
        let without_markers = domain.strip_prefix("||").unwrap_or(domain);
        let without_carets = without_markers.trim_end_matches('^').trim_end_matches('.');
        match normalize_domain(without_carets) {
            Some(normalized) => clean.push(normalized),
            None => return ModifierOutcome::Invalid,
        }
    }
    state.denyallow = Some(clean.join("|"));
    ModifierOutcome::Accepted
}

fn apply_dns_type(token: &str, is_negative: bool, state: &mut ModifierState) -> ModifierOutcome {
    let raw_spec = if is_negative {
        token[9..].trim()
    } else {
        token[8..].trim()
    };
    if raw_spec.is_empty() {
        return ModifierOutcome::Unsupported;
    }
    let raw_types: Vec<String> = raw_spec
        .split('|')
        .map(|dns_type| dns_type.trim().to_uppercase())
        .filter(|dns_type| !dns_type.is_empty())
        .collect();
    if raw_types.is_empty() {
        return ModifierOutcome::Unsupported;
    }
    let has_tilde = raw_types.iter().any(|dns_type| dns_type.starts_with('~'));
    let mut clean = Vec::with_capacity(raw_types.len());
    for dns_type in &raw_types {
        let actual = dns_type.strip_prefix('~').unwrap_or(dns_type);
        if !is_valid_dns_type(actual) {
            return ModifierOutcome::Unsupported;
        }
        clean.push(actual.to_string());
    }
    let joined = clean.join("|");
    state.dns_type = Some(if is_negative || has_tilde {
        format!("~{joined}")
    } else {
        joined
    });
    ModifierOutcome::Accepted
}

fn apply_dnsrewrite(token: &str, state: &mut ModifierState) -> ModifierOutcome {
    let raw_spec = token[11..].trim();
    if raw_spec.is_empty() {
        return ModifierOutcome::Invalid;
    }
    let target_spec = if raw_spec.contains(';') {
        dnsrewrite_last_part(raw_spec)
    } else {
        raw_spec.to_string()
    };
    let upper = target_spec.to_uppercase();
    if upper == "NXDOMAIN" || upper == "REFUSED" || upper == "SERVFAIL" || is_sinkhole(&target_spec)
    {
        state.rewrite_is_block = true;
        return ModifierOutcome::Accepted;
    }
    if looks_like_literal_ip(&target_spec) {
        let Some(address) = parse_numeric_address_safe(&target_spec) else {
            return ModifierOutcome::Invalid;
        };
        state.rewrite_type = Some(if address.contains(':') {
            REWRITE_IPV6
        } else {
            REWRITE_IPV4
        });
        state.rewrite_value = Some(address);
        return ModifierOutcome::Accepted;
    }
    let Some(cname) = normalize_domain(&target_spec) else {
        return ModifierOutcome::Invalid;
    };
    state.rewrite_type = Some(REWRITE_CNAME);
    state.rewrite_value = Some(cname);
    ModifierOutcome::Accepted
}

/// Applies the whole modifier list; the first failing token wins.
pub(crate) fn apply_modifiers(
    spec: &str,
    state: &mut ModifierState,
) -> Result<(), ModifierRejection> {
    for token in spec
        .split(',')
        .map(str::trim)
        .filter(|token| !token.is_empty())
    {
        let lower = token.to_ascii_lowercase();
        let outcome = if lower == "important" {
            state.important = true;
            ModifierOutcome::Accepted
        } else if lower.starts_with("~denyallow=") {
            // The modifier is already an exclusion list, so `~` is dropped but the rule is kept.
            ModifierOutcome::Accepted
        } else if lower.starts_with("app=") || lower.starts_with("~app=") {
            apply_app_scope(token, lower.starts_with("~app="), state)
        } else if lower.starts_with("denyallow=") {
            apply_denyallow(token, state)
        } else if lower.starts_with("dnstype=") || lower.starts_with("~dnstype=") {
            apply_dns_type(token, lower.starts_with("~dnstype="), state)
        } else if lower.starts_with("dnsrewrite=") {
            apply_dnsrewrite(token, state)
        } else if lower == "badfilter" {
            state.is_badfilter = true;
            ModifierOutcome::Accepted
        } else if is_web_only_modifier(&lower) {
            return Err(ModifierRejection::Ignored);
        } else if lower == "all" || lower == "empty" {
            // `$all` matches every content type: no extra constraint at DNS level.
            ModifierOutcome::Accepted
        } else {
            ModifierOutcome::Unsupported
        };
        match outcome {
            ModifierOutcome::Accepted => {}
            ModifierOutcome::Invalid => return Err(ModifierRejection::Invalid),
            ModifierOutcome::Unsupported => return Err(ModifierRejection::Unsupported),
        }
    }
    Ok(())
}

/// Conservative ECMAScript syntax check. Dart validates by compiling with `RegExp`; the Rust side
/// only rejects patterns that are invalid in any dialect (unbalanced groups/classes, dangling
/// escape, quantifier with nothing to repeat). A pattern Dart rejects but this accepts is stored
/// and later dropped by the Go engine, which logs the compile failure instead of failing the load.
pub(crate) fn is_valid_regex(pattern: &str) -> bool {
    if pattern.is_empty() {
        return false;
    }
    let bytes = pattern.as_bytes();
    let mut depth: i32 = 0;
    let mut in_class = false;
    let mut index = 0;
    let mut prev_atom = false;
    let mut prev_quantifier = false;
    while index < bytes.len() {
        let current = bytes[index];
        if current == b'\\' {
            if index + 1 >= bytes.len() {
                return false;
            }
            index += 2;
            prev_atom = true;
            prev_quantifier = false;
            continue;
        }
        if in_class {
            if current == b']' {
                in_class = false;
                prev_atom = true;
                prev_quantifier = false;
            }
            index += 1;
            continue;
        }
        match current {
            b'[' => {
                in_class = true;
                prev_atom = false;
                prev_quantifier = false;
                index += 1;
            }
            b']' => {
                // A lone `]` is a literal in ECMAScript.
                prev_atom = true;
                prev_quantifier = false;
                index += 1;
            }
            b'(' => {
                depth += 1;
                prev_atom = false;
                prev_quantifier = false;
                index += 1;
            }
            b')' => {
                depth -= 1;
                if depth < 0 {
                    return false;
                }
                prev_atom = true;
                prev_quantifier = false;
                index += 1;
            }
            b'*' | b'+' => {
                if !prev_atom {
                    return false;
                }
                prev_atom = false;
                prev_quantifier = true;
                index += 1;
            }
            b'?' => {
                // After an atom it is a quantifier, after a quantifier it makes it lazy, and right
                // after `(` it opens a group prefix such as `(?:`.
                let prefix = index > 0 && bytes[index - 1] == b'(';
                if !prev_atom && !prev_quantifier && !prefix {
                    return false;
                }
                prev_atom = false;
                prev_quantifier = !prefix;
                index += 1;
            }
            b'{' => match quantifier_end(bytes, index) {
                Some(end) if prev_atom => {
                    prev_atom = false;
                    prev_quantifier = true;
                    index = end;
                }
                _ => {
                    // Not a quantifier: ECMAScript treats the brace as a literal.
                    prev_atom = true;
                    prev_quantifier = false;
                    index += 1;
                }
            },
            b'|' | b'^' | b'$' => {
                prev_atom = false;
                prev_quantifier = false;
                index += 1;
            }
            _ => {
                prev_atom = true;
                prev_quantifier = false;
                index += 1;
            }
        }
    }
    depth == 0 && !in_class
}

/// End offset (just past `}`) when `{n}` / `{n,}` / `{n,m}` starts at `index`.
fn quantifier_end(bytes: &[u8], index: usize) -> Option<usize> {
    let mut cursor = index + 1;
    let start = cursor;
    while cursor < bytes.len() && bytes[cursor].is_ascii_digit() {
        cursor += 1;
    }
    if cursor == start {
        return None;
    }
    if cursor < bytes.len() && bytes[cursor] == b',' {
        cursor += 1;
        while cursor < bytes.len() && bytes[cursor].is_ascii_digit() {
            cursor += 1;
        }
    }
    if cursor < bytes.len() && bytes[cursor] == b'}' {
        return Some(cursor + 1);
    }
    None
}

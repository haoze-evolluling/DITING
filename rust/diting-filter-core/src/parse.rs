use std::net::{Ipv4Addr, Ipv6Addr};
use std::sync::OnceLock;

use diting_go_compat::dns_type::string_to_type;
use diting_go_compat::text::{go_lower, go_trim_space};
use idna::uts46::{AsciiDenyList, DnsLength, Hyphens, Uts46};

const BOM: char = '\u{feff}';

const RESERVED_DOMAINS: [&str; 4] = ["localhost", "local", "broadcasthost", "localdomain"];

const WEB_ONLY_MODIFIERS: [&str; 19] = [
    "script",
    "image",
    "stylesheet",
    "font",
    "media",
    "subdocument",
    "websocket",
    "xhr",
    "xmlhttprequest",
    "ping",
    "popup",
    "document",
    "other",
    "third-party",
    "~third-party",
    "strict-third-party",
    "strict-first-party",
    "match-case",
    "all",
];

const WEB_ONLY_MODIFIER_PREFIXES: [&str; 5] = ["domain=", "app=", "~app=", "method=", "~method="];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedLine {
    pub raw: String,
    pub pattern: String,
    pub is_allow: bool,
    pub important: bool,
    pub is_regex: bool,
    pub dns_type: u16,
    pub is_wildcard: bool,
    pub is_exact: bool,
    pub deny_allow: Vec<String>,
    pub to: Vec<String>,
    pub rewrite: Option<String>,
}

impl ParsedLine {
    fn new(raw: &str, pattern: String) -> Self {
        Self {
            raw: raw.to_string(),
            pattern,
            is_allow: false,
            important: false,
            is_regex: false,
            dns_type: 0,
            is_wildcard: false,
            is_exact: false,
            deny_allow: Vec::new(),
            to: Vec::new(),
            rewrite: None,
        }
    }
}

pub fn parse_document(text: &str) -> Vec<ParsedLine> {
    let mut out = Vec::new();
    for line in document_lines(text) {
        parse_document_line(line, &mut out);
    }
    out
}

fn parse_document_line(line: &str, out: &mut Vec<ParsedLine>) {
    let trimmed = go_trim_space(line.strip_prefix(BOM).unwrap_or(line));
    if trimmed.is_empty() || starts_with_comment(trimmed) {
        return;
    }

    let fields: Vec<&str> = trimmed.split_whitespace().collect();
    if fields.len() >= 2 && is_literal_ip(fields[0]) {
        if is_sinkhole_ip(fields[0]) {
            for host in &fields[1..] {
                let host = match host.find('#') {
                    Some(index) => &host[..index],
                    None => host,
                };
                if let Some(pattern) = normalize_domain(host) {
                    out.push(ParsedLine::new(line, pattern));
                }
            }
        }
        return;
    }

    if let Some(parsed) = parse_line(line) {
        out.push(parsed);
    }
}

fn document_lines(text: &str) -> impl Iterator<Item = &str> {
    text.split_terminator('\n')
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
}

pub fn parse_line(line: &str) -> Option<ParsedLine> {
    let raw = line;
    let mut rest = go_trim_space(line.strip_prefix(BOM).unwrap_or(line));

    if rest.is_empty() || starts_with_comment(rest) {
        return None;
    }

    if is_cosmetic_or_script_rule(rest) {
        return None;
    }

    if !rest.starts_with('/') {
        rest = go_trim_space(split_once_byte(rest, b'#').0);
        if rest.is_empty() {
            return None;
        }
    }

    let fields: Vec<&str> = rest.split_whitespace().collect();
    if fields.len() >= 2 && is_literal_ip(fields[0]) {
        if !is_sinkhole_ip(fields[0]) {
            return None;
        }
        let pattern = normalize_domain(fields[1])?;
        return Some(ParsedLine::new(raw, pattern));
    }

    let mut is_allow = false;
    if let Some(without_exception) = rest.strip_prefix("@@") {
        is_allow = true;
        rest = without_exception;
    }

    let mut important = false;
    let mut dns_type = 0u16;
    let mut deny_allow: Vec<String> = Vec::new();
    let mut to_domains: Vec<String> = Vec::new();
    let mut rewrite: Option<String> = None;

    let mut modifier_part = "";
    if rest.starts_with('/') {
        if let Some(last_slash) = last_index_byte(rest, b'/') {
            if last_slash > 0 && last_slash < rest.len() - 1 {
                let remainder = &rest[last_slash + 1..];
                if let Some(dollar) = remainder.find('$') {
                    modifier_part = &remainder[dollar + 1..];
                    rest = &rest[..last_slash + 1];
                }
            }
        }
    } else if let Some(dollar) = rest.find('$') {
        modifier_part = &rest[dollar + 1..];
        rest = go_trim_space(&rest[..dollar]);
    }

    if !modifier_part.is_empty() {
        for raw_modifier in split_modifiers(modifier_part) {
            let modifier = go_lower(go_trim_space(&raw_modifier));
            if modifier == "important" {
                important = true;
            } else if modifier == "badfilter" {
                return None;
            } else if let Some(type_token) = modifier.strip_prefix("dnstype=") {
                if let Some(value) = string_to_type(&type_token.to_uppercase()) {
                    dns_type = value;
                }
            } else if let Some(value) = modifier.strip_prefix("denyallow=") {
                deny_allow = parse_modifier_domains(value);
            } else if let Some(value) = modifier.strip_prefix("to=") {
                to_domains = parse_modifier_domains(value);
            } else if modifier == "dnsrewrite" || modifier.starts_with("dnsrewrite=") {
                rewrite = Some(dns_rewrite_value(&raw_modifier).to_string());
            } else if modifier.starts_with("~denyallow=") || modifier.starts_with("~to=") {
            } else if is_web_only_modifier(&modifier) {
                return None;
            }
        }
    }

    if rest.len() > 2 && rest.starts_with('/') && rest.ends_with('/') {
        let pattern = &rest[1..rest.len() - 1];
        let mut parsed = ParsedLine::new(raw, pattern.to_string());
        parsed.is_allow = is_allow;
        parsed.important = important;
        parsed.is_regex = true;
        parsed.dns_type = dns_type;
        parsed.deny_allow = deny_allow;
        parsed.to = to_domains;
        parsed.rewrite = rewrite;
        return Some(parsed);
    }

    let mut is_exact = false;
    let domain_tail = if let Some(without_prefix) = rest.strip_prefix("||") {
        let stripped = without_prefix.strip_suffix('^').unwrap_or(without_prefix);
        match stripped.strip_suffix('|') {
            Some(exact) => {
                is_exact = true;
                exact
            }
            None => stripped,
        }
    } else if rest.starts_with('|') && rest.ends_with('|') {
        is_exact = true;
        rest.trim_matches('|')
    } else if let Some(without_suffix) = rest.strip_suffix('|') {
        is_exact = true;
        without_suffix.strip_suffix('^').unwrap_or(without_suffix)
    } else if let Some(without_prefix) = rest.strip_prefix('|') {
        without_prefix.strip_suffix('^').unwrap_or(without_prefix)
    } else {
        rest.strip_suffix('^').unwrap_or(rest)
    };

    let domain = go_trim_space(domain_tail);
    if domain.is_empty() || domain.contains(['/', '?', '#']) {
        return None;
    }

    let is_wildcard = domain.contains('*');
    let pattern = if is_wildcard {
        normalize_wildcard_domain(domain)?
    } else {
        normalize_domain(domain)?
    };

    let mut parsed = ParsedLine::new(raw, pattern);
    parsed.is_allow = is_allow;
    parsed.important = important;
    parsed.dns_type = dns_type;
    parsed.is_wildcard = is_wildcard;
    parsed.is_exact = is_exact;
    parsed.deny_allow = deny_allow;
    parsed.to = to_domains;
    parsed.rewrite = rewrite;
    Some(parsed)
}

fn starts_with_comment(line: &str) -> bool {
    matches!(
        line.as_bytes().first(),
        Some(b'!') | Some(b'#') | Some(b'[')
    )
}

fn is_cosmetic_or_script_rule(line: &str) -> bool {
    const MARKERS: [&str; 8] = ["##", "#@#", "#?#", "#@?#", "#$#", "#@$#", "#%#", "#@%#"];
    MARKERS.iter().any(|marker| line.contains(*marker))
}

fn split_once_byte(line: &str, separator: u8) -> (&str, &str) {
    match line.as_bytes().iter().position(|byte| *byte == separator) {
        Some(index) => (&line[..index], &line[index + 1..]),
        None => (line, ""),
    }
}

fn last_index_byte(line: &str, separator: u8) -> Option<usize> {
    line.as_bytes().iter().rposition(|byte| *byte == separator)
}

fn split_modifiers(modifier_part: &str) -> Vec<String> {
    let Some((head, tail)) = cut_rewrite_modifier(modifier_part) else {
        return modifier_part.split(',').map(str::to_string).collect();
    };

    let mut merged = head;
    let mut segments = tail.split(',');
    let mut current = segments.next().unwrap_or("").to_string();
    for segment in segments {
        if looks_like_modifier(segment) {
            merged.push(current);
            current = segment.to_string();
        } else {
            current.push(',');
            current.push_str(segment);
        }
    }
    merged.push(current);
    merged
}

fn cut_rewrite_modifier(modifier_part: &str) -> Option<(Vec<String>, &str)> {
    let mut offset = 0usize;
    loop {
        let end = match modifier_part[offset..].find(',') {
            Some(index) => offset + index,
            None => modifier_part.len(),
        };

        let segment = go_lower(go_trim_space(&modifier_part[offset..end]));
        if segment == "dnsrewrite" || segment.starts_with("dnsrewrite=") {
            let prefix = go_trim_space(&modifier_part[..offset]).trim_matches(',');
            let head = if prefix.is_empty() {
                Vec::new()
            } else {
                prefix.split(',').map(str::to_string).collect()
            };
            return Some((head, &modifier_part[offset..]));
        }

        if end == modifier_part.len() {
            return None;
        }
        offset = end + 1;
    }
}

fn looks_like_modifier(segment: &str) -> bool {
    let modifier = go_lower(go_trim_space(segment));
    if modifier.is_empty() {
        return true;
    }
    if modifier == "important" || modifier == "badfilter" || modifier == "dnsrewrite" {
        return true;
    }
    if modifier.starts_with("dnsrewrite=")
        || modifier.starts_with("dnstype=")
        || modifier.starts_with("denyallow=")
        || modifier.starts_with("to=")
        || modifier.starts_with("~denyallow=")
        || modifier.starts_with("~to=")
    {
        return true;
    }
    is_web_only_modifier(&modifier)
}

fn dns_rewrite_value(raw_modifier: &str) -> &str {
    match raw_modifier.find('=') {
        Some(index) => &raw_modifier[index + 1..],
        None => "",
    }
}

fn parse_modifier_domains(raw: &str) -> Vec<String> {
    if raw.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for part in raw.split('|') {
        let part = go_lower(go_trim_space(part));
        if part.is_empty() || part.starts_with('~') {
            continue;
        }
        let part = part.strip_prefix('*').unwrap_or(&part);
        let part = part.trim_matches('.');
        let part = part.strip_suffix('^').unwrap_or(part);
        if part.is_empty() || part.contains(['/', '?', '#', '*']) {
            continue;
        }
        out.push(part.to_string());
    }
    out
}

fn is_literal_ip(value: &str) -> bool {
    value == "0" || parse_ip(value)
}

fn parse_ip(value: &str) -> bool {
    if value.parse::<Ipv4Addr>().is_ok() {
        return true;
    }
    value.parse::<Ipv6Addr>().is_ok()
}

fn is_sinkhole_ip(value: &str) -> bool {
    matches!(
        go_lower(value).as_ref(),
        "0" | "0.0.0.0" | "127.0.0.1" | "::" | "::1"
    )
}

fn normalize_domain(domain: &str) -> Option<String> {
    let lowered = go_lower(go_trim_space(domain));
    let candidate = lowered.strip_suffix('.').unwrap_or(&lowered);
    if candidate.is_empty() || !candidate.contains('.') {
        return None;
    }
    if RESERVED_DOMAINS.contains(&candidate) {
        return None;
    }
    if parse_ip(candidate) {
        return None;
    }
    let ascii = uts46()
        .to_ascii(
            candidate.as_bytes(),
            AsciiDenyList::STD3,
            Hyphens::Check,
            DnsLength::Ignore,
        )
        .ok()?;
    if ascii.len() > 253 {
        return None;
    }
    let lower = ascii.as_ref().to_ascii_lowercase();
    Some(lower)
}

fn normalize_wildcard_domain(pattern: &str) -> Option<String> {
    let lowered = go_lower(go_trim_space(pattern));
    let candidate = lowered.strip_suffix('.').unwrap_or(&lowered);
    if candidate.is_empty() || candidate == "*" {
        return Some("*".to_string());
    }
    if candidate.len() > 253 {
        return None;
    }
    for label in candidate.split('.') {
        if label.is_empty() || label.len() > 63 {
            return None;
        }
        let valid = label
            .bytes()
            .all(|byte| matches!(byte, b'a'..=b'z' | b'0'..=b'9' | b'-' | b'*' | b'_'));
        if !valid {
            return None;
        }
    }
    Some(candidate.to_string())
}

fn is_web_only_modifier(modifier: &str) -> bool {
    if WEB_ONLY_MODIFIERS.contains(&modifier) {
        return true;
    }
    WEB_ONLY_MODIFIER_PREFIXES
        .iter()
        .any(|prefix| modifier.starts_with(prefix))
}

#[cfg(test)]
mod tests;

fn uts46() -> &'static Uts46 {
    static LOOKUP: OnceLock<Uts46> = OnceLock::new();
    LOOKUP.get_or_init(Uts46::new)
}

//! Parses hosts and dnsmasq lines; the target address picks the kind: sinkhole = block, IP =
//! rewrite, domain = CNAME. Port of `hosts_parser.dart`.

use crate::domain::{
    looks_like_literal_ip, normalize_domain, normalize_wildcard_domain, parse_numeric_address_safe,
    SINKHOLE_ADDRESSES,
};
use crate::models::{
    CategorizedLine, ParsedRewriteRule, ParsedRule, REWRITE_CNAME, REWRITE_IPV4, REWRITE_IPV6,
};

fn rewrite_type_for(address: &str) -> &'static str {
    if address.contains(':') {
        REWRITE_IPV6
    } else {
        REWRITE_IPV4
    }
}

fn sinkhole_contains(value: &str) -> bool {
    SINKHOLE_ADDRESSES.contains(&value.to_ascii_lowercase().as_str())
}

/// `address=/domain/ip`, `server=/domain/ip`, `address=/domain/`.
pub fn parse_dnsmasq_line(line: &str, original: &str) -> CategorizedLine {
    let mut content = line;
    if let Some(index) = line.find(" #") {
        content = &line[..index];
    } else if let Some(index) = line.find("\t#") {
        content = &line[..index];
    }
    let content = content.trim();

    let without_prefix = content
        .strip_prefix("address=/")
        .or_else(|| content.strip_prefix("server=/"))
        .unwrap_or(content);
    let parts: Vec<&str> = without_prefix.split('/').collect();
    if parts.len() < 2 {
        return CategorizedLine::invalid();
    }

    let target = parts[parts.len() - 1].trim();
    let domain_parts: Vec<&str> = parts[..parts.len() - 1]
        .iter()
        .map(|part| part.trim())
        .filter(|part| !part.is_empty())
        .collect();
    if domain_parts.is_empty() {
        return CategorizedLine::invalid();
    }

    let is_sinkhole_target = target.is_empty() || target == "#" || sinkhole_contains(target);

    if is_sinkhole_target {
        let mut block_rules = Vec::new();
        let mut invalid = 0u32;
        for domain in &domain_parts {
            let is_wildcard = domain.contains('*');
            let normalized = if is_wildcard {
                normalize_wildcard_domain(domain)
            } else {
                normalize_domain(domain)
            };
            match normalized {
                Some(pattern) => {
                    let mut rule = ParsedRule::new(pattern, original.to_string());
                    rule.is_wildcard = is_wildcard;
                    block_rules.push(rule);
                }
                None => invalid += 1,
            }
        }
        if block_rules.is_empty() && invalid > 0 {
            return CategorizedLine::invalid_n(invalid);
        }
        return CategorizedLine {
            block_rules,
            invalid_count: invalid,
            ..CategorizedLine::default()
        };
    }

    if looks_like_literal_ip(target) {
        if let Some(address) = parse_numeric_address_safe(target) {
            let target_type = rewrite_type_for(&address);
            let mut rewrite_rules = Vec::new();
            let mut invalid = 0u32;
            for domain in &domain_parts {
                match normalize_domain(domain) {
                    Some(pattern) => rewrite_rules.push(ParsedRewriteRule {
                        pattern,
                        target_type: target_type.to_string(),
                        target_value: address.clone(),
                        raw_line: original.to_string(),
                    }),
                    None => invalid += 1,
                }
            }
            if rewrite_rules.is_empty() && invalid > 0 {
                return CategorizedLine::invalid_n(invalid);
            }
            return CategorizedLine {
                rewrite_rules,
                invalid_count: invalid,
                ..CategorizedLine::default()
            };
        }
    }

    if let Some(target_domain) = normalize_domain(target) {
        let mut rewrite_rules = Vec::new();
        let mut invalid = 0u32;
        for domain in &domain_parts {
            match normalize_domain(domain) {
                Some(pattern) => rewrite_rules.push(ParsedRewriteRule {
                    pattern,
                    target_type: REWRITE_CNAME.to_string(),
                    target_value: target_domain.clone(),
                    raw_line: original.to_string(),
                }),
                None => invalid += 1,
            }
        }
        if rewrite_rules.is_empty() && invalid > 0 {
            return CategorizedLine::invalid_n(invalid);
        }
        return CategorizedLine {
            rewrite_rules,
            invalid_count: invalid,
            ..CategorizedLine::default()
        };
    }

    CategorizedLine::invalid()
}

/// `IP domain1 [domain2 ...]`; `None` when not a hosts line.
pub fn parse_hosts_line_detailed(line: &str, original: &str) -> Option<CategorizedLine> {
    let content = match line.find('#') {
        Some(index) => line[..index].trim(),
        None => line.trim(),
    };
    // Cheap rejection first: this runs for every line before the adblock branch, so it must not
    // allocate until the line is known to be a hosts line.
    let mut fields = content.split_whitespace();
    let first = fields.next()?;
    let second = fields.next()?;
    if !looks_like_literal_ip(first) {
        return None;
    }
    let hosts: Vec<&str> = std::iter::once(second).chain(fields).collect();
    let mut invalid = 0u32;

    if sinkhole_contains(first) {
        let mut block_rules = Vec::new();
        for host in &hosts {
            match normalize_domain(host) {
                Some(pattern) => block_rules.push(ParsedRule::new(pattern, original.to_string())),
                None => invalid += 1,
            }
        }
        if block_rules.is_empty() && invalid > 0 {
            return Some(CategorizedLine::invalid_n(invalid));
        }
        return Some(CategorizedLine {
            block_rules,
            invalid_count: invalid,
            ..CategorizedLine::default()
        });
    }

    let Some(address) = parse_numeric_address_safe(first) else {
        return Some(CategorizedLine::invalid());
    };
    let target_type = rewrite_type_for(&address);
    let mut rewrite_rules = Vec::new();
    for host in &hosts {
        match normalize_domain(host) {
            Some(pattern) => rewrite_rules.push(ParsedRewriteRule {
                pattern,
                target_type: target_type.to_string(),
                target_value: address.clone(),
                raw_line: original.to_string(),
            }),
            None => invalid += 1,
        }
    }
    if rewrite_rules.is_empty() && invalid > 0 {
        return Some(CategorizedLine::invalid_n(invalid));
    }
    Some(CategorizedLine {
        rewrite_rules,
        invalid_count: invalid,
        ..CategorizedLine::default()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hosts_block_lines() {
        let parsed = parse_hosts_line_detailed("0.0.0.0 ads.example.com tracker.example.net", "x")
            .expect("hosts line");
        let patterns: Vec<&str> = parsed
            .block_rules
            .iter()
            .map(|r| r.pattern.as_str())
            .collect();
        assert_eq!(patterns, ["ads.example.com", "tracker.example.net"]);
    }

    #[test]
    fn parses_hosts_rewrite_lines() {
        let parsed = parse_hosts_line_detailed("1.2.3.4 a.example.com", "x").expect("hosts line");
        assert_eq!(parsed.rewrite_rules.len(), 1);
        assert_eq!(parsed.rewrite_rules[0].target_type, REWRITE_IPV4);
        assert_eq!(parsed.rewrite_rules[0].target_value, "1.2.3.4");
    }

    #[test]
    fn ignores_non_hosts_lines() {
        assert!(parse_hosts_line_detailed("example.com", "x").is_none());
        assert!(parse_hosts_line_detailed("||a.com^", "x").is_none());
    }

    #[test]
    fn parses_dnsmasq_lines() {
        let block = parse_dnsmasq_line("address=/ads.example.com/", "x");
        assert_eq!(block.block_rules.len(), 1);
        assert_eq!(block.block_rules[0].pattern, "ads.example.com");

        let rewrite = parse_dnsmasq_line("server=/a.example.com/1.2.3.4", "x");
        assert_eq!(rewrite.rewrite_rules.len(), 1);
        assert_eq!(rewrite.rewrite_rules[0].target_type, REWRITE_IPV4);

        let cname = parse_dnsmasq_line("address=/a.example.com/b.example.com", "x");
        assert_eq!(cname.rewrite_rules[0].target_type, REWRITE_CNAME);

        // `1.2.3.4.5` is not a literal IP but is still a shape-valid domain, so it becomes the
        // CNAME target — same as the Dart implementation.
        let odd = parse_dnsmasq_line("address=/a.example.com/1.2.3.4.5", "x");
        assert_eq!(odd.rewrite_rules[0].target_type, REWRITE_CNAME);
        assert_eq!(odd.rewrite_rules[0].target_value, "1.2.3.4.5");
    }
}

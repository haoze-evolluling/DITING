//! Forced SafeSearch (`safesearch.go` + `safesearch_rules.go`).
//!
//! The rule table is fixed at compile time and compiled once per configuration change. A lookup
//! only fires for A / AAAA / HTTPS queries, and only when the global switch and the individual
//! provider are enabled — the same scope AdGuard Home's `CheckHost` uses.

mod rules;

use std::collections::{HashMap, HashSet};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::RwLock;

use diting_desktop_api::config::SafeSearchConfig;

use rules::RULE_TEXTS;

/// TTL applied to forced-SafeSearch answers.
pub const DEFAULT_SAFESEARCH_TTL: u32 = 300;

/// Numeric query types that participate.
const TYPE_A: u16 = 1;
const TYPE_AAAA: u16 = 28;
const TYPE_HTTPS: u16 = 65;

/// Built-in service identifiers, in the stable order the UI uses.
pub const SERVICES: [&str; 7] = [
    "bing",
    "duckduckgo",
    "ecosia",
    "google",
    "pixabay",
    "yandex",
    "youtube",
];

/// A forced-SafeSearch hit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SafeSearchResult {
    /// Service that owns the matched domain.
    pub service: String,
    /// CNAME target (FQDN with a trailing dot), empty for an address rewrite.
    pub cname: String,
    /// A/AAAA target address, if the rule rewrites to one.
    pub ip: Option<IpAddr>,
    /// Numeric type of [`Self::ip`], `0` when there is none.
    pub ip_type: u16,
    /// The rule matched but has no answer for this query type.
    pub nodata: bool,
}

/// Runtime projection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SafeSearchStats {
    pub enabled: bool,
    pub services: Vec<String>,
    pub disabled: Vec<String>,
    pub ttl: u32,
}

#[derive(Debug, Clone)]
struct Rule {
    service: String,
    cname: String,
    ip: Option<IpAddr>,
    ip_type: u16,
}

struct Compiled {
    enabled: bool,
    ttl: u32,
    disabled: HashSet<String>,
    disabled_list: Vec<String>,
    by_domain: HashMap<String, Rule>,
}

/// Forced-SafeSearch engine.
pub struct SafeSearchEngine {
    state: RwLock<Compiled>,
}

impl SafeSearchEngine {
    /// Creates and compiles the engine.
    pub fn new(config: &SafeSearchConfig) -> Self {
        Self {
            state: RwLock::new(compile(config)),
        }
    }

    /// Replaces the configuration and recompiles the rule index.
    pub fn configure(&self, config: &SafeSearchConfig) {
        let compiled = compile(config);
        *self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner()) = compiled;
    }

    /// Global switch.
    pub fn enabled(&self) -> bool {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .enabled
    }

    /// Looks `domain` up for `qtype`; `None` when the engine does not take over the name.
    pub fn lookup(&self, domain: &str, qtype: u16) -> Option<SafeSearchResult> {
        if !matches!(qtype, TYPE_A | TYPE_AAAA | TYPE_HTTPS) {
            return None;
        }
        let normalized = normalize_domain(domain);
        if normalized.is_empty() {
            return None;
        }
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        if !state.enabled {
            return None;
        }
        let rule = state.by_domain.get(&normalized)?;
        if state.disabled.contains(&rule.service) {
            return None;
        }
        let mut result = SafeSearchResult {
            service: rule.service.clone(),
            cname: String::new(),
            ip: None,
            ip_type: 0,
            nodata: false,
        };
        if !rule.cname.is_empty() {
            result.cname = rule.cname.clone();
        } else if rule.ip.is_some() && rule.ip_type == qtype {
            result.ip = rule.ip;
            result.ip_type = rule.ip_type;
        } else {
            // Matched rule without a record of this query type (e.g. Yandex AAAA/HTTPS).
            result.nodata = true;
        }
        Some(result)
    }

    /// All built-in service identifiers.
    pub fn services(&self) -> Vec<&'static str> {
        SERVICES.to_vec()
    }

    /// Runtime projection.
    pub fn stats(&self) -> SafeSearchStats {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        SafeSearchStats {
            enabled: state.enabled,
            services: SERVICES.iter().map(|service| service.to_string()).collect(),
            disabled: state.disabled_list.clone(),
            ttl: state.ttl,
        }
    }
}

/// The default TTL (`DefaultSafeSearchTTL`).
pub fn default_ttl() -> u32 {
    DEFAULT_SAFESEARCH_TTL
}

fn compile(config: &SafeSearchConfig) -> Compiled {
    let mut by_domain = HashMap::new();
    for (service, text) in RULE_TEXTS {
        for line in text.lines() {
            if let Some((domain, rule)) = parse_rule_line(line, service) {
                by_domain.insert(domain, rule);
            }
        }
    }
    let disabled_list = config.disabled.clone();
    let disabled: HashSet<String> = disabled_list.iter().cloned().collect();
    Compiled {
        enabled: config.enabled,
        ttl: if config.ttl == 0 {
            DEFAULT_SAFESEARCH_TTL
        } else {
            config.ttl
        },
        disabled,
        disabled_list,
        by_domain,
    }
}

/// Parses `|domain^$dnsrewrite=NOERROR;<TYPE>;<VALUE>`; returns the normalized domain and rule.
fn parse_rule_line(line: &str, service: &str) -> Option<(String, Rule)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('!') || line.starts_with('#') {
        return None;
    }
    let (domain_part, modifier) = match line.find('$') {
        Some(index) => (&line[..index], &line[index + 1..]),
        None => (line, ""),
    };
    let domain_part = domain_part.strip_prefix('|').unwrap_or(domain_part);
    let domain_part = domain_part.strip_suffix('^').unwrap_or(domain_part);
    let domain = normalize_domain(domain_part);
    if domain.is_empty() || !modifier.starts_with("dnsrewrite=") {
        return None;
    }

    let payload = &modifier["dnsrewrite=".len()..];
    let parts: Vec<&str> = payload.splitn(3, ';').collect();
    if parts.len() != 3 {
        return None;
    }
    let type_name = parts[1].trim().to_ascii_uppercase();
    let value = parts[2].trim();

    let mut rule = Rule {
        service: service.to_string(),
        cname: String::new(),
        ip: None,
        ip_type: 0,
    };
    match type_name.as_str() {
        "CNAME" => {
            if value.is_empty() {
                return None;
            }
            rule.cname = fqdn(&normalize_domain(value));
        }
        "A" => {
            rule.ip = Some(IpAddr::V4(parse_ipv4(value)?));
            rule.ip_type = TYPE_A;
        }
        "AAAA" => {
            rule.ip = Some(IpAddr::V6(parse_ipv6(value)?));
            rule.ip_type = TYPE_AAAA;
        }
        _ => return None,
    }
    Some((domain, rule))
}

/// `net.ParseIP` + `To4`.
fn parse_ipv4(value: &str) -> Option<Ipv4Addr> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(address);
    }
    value.parse::<Ipv6Addr>().ok()?.to_ipv4_mapped()
}

/// `net.ParseIP` + `To16`: an IPv4 literal becomes its v4-mapped IPv6 form.
fn parse_ipv6(value: &str) -> Option<Ipv6Addr> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(address.to_ipv6_mapped());
    }
    value.parse::<Ipv6Addr>().ok()
}

/// `normalizeRewriteDomain`: trim whitespace, lowercase, trim leading/trailing dots.
fn normalize_domain(domain: &str) -> String {
    domain.trim().to_lowercase().trim_matches('.').to_string()
}

fn fqdn(name: &str) -> String {
    if name.is_empty() {
        ".".to_string()
    } else if name.ends_with('.') {
        name.to_string()
    } else {
        format!("{name}.")
    }
}

#[cfg(test)]
mod tests;

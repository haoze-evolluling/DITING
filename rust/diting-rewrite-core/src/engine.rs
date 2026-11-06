//! The rewrite engine: the configuration Go used to compile into `exactRules`, `wildcardRules`
//! and `ptrMap`, plus the query walk that turns it into answer records.
//!
//! Go still owns the configuration (`RewriteRule` is JSON on the IPC surface) and its mutation
//! (`AddRule` / `DeleteRule` / `Configure` rebuild the whole list). Everything that *interprets*
//! that list lives here:
//!
//! * domain normalization, exact and wildcard indexes, longest-suffix-first order;
//! * shortcut `IPs` / `CNAME` / `TXT` fields and the explicit `Records` list, compiled once at
//!   build time instead of on every query;
//! * the automatic PTR map (exact rules only) and reverse-name lookup;
//! * rcode overrides, NODATA semantics and the CNAME chase with cycle/depth protection;
//! * RFC 1034 §3.6.2 owner merging, so a CNAME and other records never answer for the same name.
//!
//! The rules and their observable answers are the ones `rewrite.go` / `rewrite_lookup.go` shipped;
//! the Go tests covering them now run through this module unchanged. `dns.RR` construction stays in
//! Go because the answer goes straight into a `dns.Msg`.

use std::collections::HashMap;
use std::net::{Ipv4Addr, Ipv6Addr};

use diting_go_compat::dns_type;
use diting_go_compat::text::{go_lower, go_trim_space, go_upper};

use crate::record::{self, mapped_ipv4, Record, TYPE_A, TYPE_AAAA, TYPE_CNAME, TYPE_TXT};

/// `DefaultRewriteTTL`: the TTL when neither the rule nor the config sets one.
pub const DEFAULT_TTL: u32 = 60;

/// `dns.RcodeSuccess` and the codes a rewrite rule may override with.
const RCODE_SUCCESS: u16 = 0;

/// One configured explicit record, still in text form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecordSpec {
    /// Configured type name (`"MX"`, `"HTTPS"`, ...).
    pub type_name: String,
    /// Configured value text.
    pub value: String,
}

/// One configured rewrite rule, mirroring the Go `RewriteRule` JSON fields.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleConfig {
    /// Match domain; `*.lower` is a wildcard.
    pub domain: String,
    /// Shortcut A/AAAA targets.
    pub ips: Vec<String>,
    /// Shortcut CNAME target; empty means none.
    pub cname: String,
    /// Shortcut TXT strings, answered as one TXT record.
    pub txt: Vec<String>,
    /// Rule TTL; `0` means the engine default.
    pub ttl: u32,
    /// Explicit records.
    pub records: Vec<RecordSpec>,
    /// Answer-code override name; empty means none.
    pub rcode: String,
}

/// One engine snapshot request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    /// Whether lookups are enabled at all.
    pub enabled: bool,
    /// Engine default TTL.
    pub default_ttl: u32,
    /// Rules in configuration order.
    pub rules: Vec<RuleConfig>,
}

/// One answer record ready to cross the boundary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Answer {
    /// Owner name (`dns.Fqdn` of the query or the chased target).
    pub owner: String,
    /// TTL the rule asked for.
    pub ttl: u32,
    /// Record body.
    pub record: Record,
}

/// The result of one lookup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LookupResult {
    /// `true` means the name belongs to a rule; an empty answer list is authoritative NODATA.
    pub matched: bool,
    /// Rcode override (`RCODE_SUCCESS` unless the rule set one).
    pub rcode: u16,
    /// Answer records in the order the old engine produced them.
    pub answers: Vec<Answer>,
}

impl LookupResult {
    fn unmatched() -> Self {
        Self {
            matched: false,
            rcode: RCODE_SUCCESS,
            answers: Vec::new(),
        }
    }
}

/// PTR map key: the canonical address bytes, so Go and Rust never have to agree on a text form.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum IpKey {
    V4([u8; 4]),
    V6([u8; 16]),
}

/// One compiled rule.
#[derive(Debug, Clone)]
struct CompiledRule {
    is_wildcard: bool,
    suffix: String,
    v4: Vec<[u8; 4]>,
    v6: Vec<[u8; 16]>,
    cname: String,
    txt: Vec<String>,
    ttl: u32,
    records: Vec<Record>,
    rcode: u16,
}

/// The engine snapshot; Go holds one per configuration and swaps it atomically.
pub struct Engine {
    enabled: bool,
    default_ttl: u32,
    exact: HashMap<String, CompiledRule>,
    wildcard: Vec<CompiledRule>,
    ptr: HashMap<IpKey, Vec<String>>,
}

impl Engine {
    /// Compiles `config`. Warnings are the lines the old Go code logged while dropping an
    /// unrecognised rcode or an invalid explicit record; Go still owns the log sink.
    pub fn build(config: &Config) -> (Self, Vec<String>) {
        let default_ttl = if config.default_ttl == 0 {
            DEFAULT_TTL
        } else {
            config.default_ttl
        };
        let mut engine = Self {
            enabled: config.enabled,
            default_ttl,
            exact: HashMap::new(),
            wildcard: Vec::new(),
            ptr: HashMap::new(),
        };
        let mut warnings = Vec::new();
        for rule in &config.rules {
            engine.add_rule(rule, &mut warnings);
        }
        // Longest suffix first, ties in configuration order (`sort.SliceStable`).
        engine
            .wildcard
            .sort_by_key(|rule| std::cmp::Reverse(rule.suffix.len()));
        (engine, warnings)
    }

    /// Compiles one rule and inserts it. An empty normalized domain is dropped without a warning,
    /// like the old `addRuleInternal`.
    fn add_rule(&mut self, rule: &RuleConfig, warnings: &mut Vec<String>) {
        let Some(compiled) = compile_rule(rule, self.default_ttl, warnings) else {
            return;
        };
        for (key, fqdn) in &compiled.ptr {
            let domains = self.ptr.entry(*key).or_default();
            if !domains.iter().any(|existing| existing == fqdn) {
                domains.push(fqdn.clone());
            }
        }
        if compiled.rule.is_wildcard {
            self.wildcard.push(compiled.rule);
        } else {
            // A later rule with the same exact domain replaces the earlier one.
            self.exact.insert(compiled.domain, compiled.rule);
        }
    }

    /// Whether lookups are enabled.
    pub fn enabled(&self) -> bool {
        self.enabled
    }

    /// The engine default TTL (PTR answers use it).
    pub fn default_ttl(&self) -> u32 {
        self.default_ttl
    }

    /// Looks `domain` up for `qtype`.
    pub fn lookup(&self, domain: &str, qtype: u16) -> LookupResult {
        if !self.enabled {
            return LookupResult::unmatched();
        }
        let norm = normalize_domain(domain);
        if norm.is_empty() {
            return LookupResult::unmatched();
        }
        let Some(rule) = self.find_rule(&norm) else {
            return LookupResult::unmatched();
        };
        if rule.rcode != RCODE_SUCCESS {
            return LookupResult {
                matched: true,
                rcode: rule.rcode,
                answers: Vec::new(),
            };
        }

        let fqdn = query_fqdn(domain);
        let mut answers = Vec::new();
        self.shortcut(rule, &fqdn, &norm, qtype, &mut answers);
        self.explicit(rule, &fqdn, qtype, &mut answers);
        LookupResult {
            matched: true,
            rcode: RCODE_SUCCESS,
            answers: merge_owner_cname(answers),
        }
    }

    fn find_rule(&self, norm: &str) -> Option<&CompiledRule> {
        if let Some(rule) = self.exact.get(norm) {
            return Some(rule);
        }
        self.wildcard
            .iter()
            .find(|rule| norm == rule.suffix || norm.ends_with(&format!(".{}", rule.suffix)))
    }

    /// The shortcut `IPs` / `CNAME` / `TXT` fields.
    fn shortcut(
        &self,
        rule: &CompiledRule,
        fqdn: &str,
        norm: &str,
        qtype: u16,
        out: &mut Vec<Answer>,
    ) {
        match qtype {
            TYPE_A => {
                if !rule.v4.is_empty() {
                    for address in &rule.v4 {
                        out.push(answer(fqdn, rule.ttl, Record::A(*address)));
                    }
                } else if !rule.cname.is_empty() {
                    out.push(answer(fqdn, rule.ttl, Record::Cname(rule.cname.clone())));
                    self.chase(&rule.cname, TYPE_A, &mut vec![norm.to_string()], out);
                }
            }
            TYPE_AAAA => {
                if !rule.v6.is_empty() {
                    for address in &rule.v6 {
                        out.push(answer(fqdn, rule.ttl, Record::Aaaa(*address)));
                    }
                } else if !rule.cname.is_empty() {
                    out.push(answer(fqdn, rule.ttl, Record::Cname(rule.cname.clone())));
                    self.chase(&rule.cname, TYPE_AAAA, &mut vec![norm.to_string()], out);
                }
            }
            TYPE_CNAME if !rule.cname.is_empty() => {
                out.push(answer(fqdn, rule.ttl, Record::Cname(rule.cname.clone())));
            }
            TYPE_TXT if !rule.txt.is_empty() => {
                out.push(answer(fqdn, rule.ttl, Record::Txt(rule.txt.clone())));
            }
            _ => {}
        }
    }

    /// Follows a CNAME target through other rules, appending the chain. Same depth limit and
    /// visited set as the old `chaseCNAME`.
    fn chase(&self, target: &str, qtype: u16, visited: &mut Vec<String>, out: &mut Vec<Answer>) {
        if visited.len() > 8 {
            return;
        }
        let norm = normalize_domain(target);
        if norm.is_empty() || visited.contains(&norm) {
            return;
        }
        visited.push(norm.clone());
        let Some(rule) = self.find_rule(&norm) else {
            return;
        };
        let owner = record::fqdn(target);
        match qtype {
            TYPE_A if !rule.v4.is_empty() => {
                for address in &rule.v4 {
                    out.push(answer(&owner, rule.ttl, Record::A(*address)));
                }
            }
            TYPE_AAAA if !rule.v6.is_empty() => {
                for address in &rule.v6 {
                    out.push(answer(&owner, rule.ttl, Record::Aaaa(*address)));
                }
            }
            TYPE_A | TYPE_AAAA if !rule.cname.is_empty() => {
                out.push(answer(&owner, rule.ttl, Record::Cname(rule.cname.clone())));
                self.chase(&rule.cname, qtype, visited, out);
            }
            _ => {}
        }
    }

    /// The explicit `Records` list. Values were validated at build time, so only the query-type
    /// filter (CNAME answers every type) and the owner name remain.
    fn explicit(&self, rule: &CompiledRule, fqdn: &str, qtype: u16, out: &mut Vec<Answer>) {
        let owner = record::fqdn(fqdn);
        for record in &rule.records {
            let rrtype = record.rrtype();
            if rrtype != TYPE_CNAME && rrtype != qtype {
                continue;
            }
            out.push(answer(&owner, rule.ttl, record.clone()));
        }
    }

    /// PTR targets for an address; empty when the engine is disabled or nothing maps.
    pub fn lookup_ptr(&self, ip: &[u8]) -> Vec<String> {
        if !self.enabled {
            return Vec::new();
        }
        let Some(key) = ip_key_bytes(ip) else {
            return Vec::new();
        };
        self.ptr.get(&key).cloned().unwrap_or_default()
    }

    /// The first PTR target, dot-trimmed here the way Go trimmed it after lookup.
    pub fn lookup_reverse(&self, ip: &[u8]) -> String {
        if !self.enabled {
            return String::new();
        }
        let Some(key) = ip_key_bytes(ip) else {
            return String::new();
        };
        self.ptr
            .get(&key)
            .and_then(|domains| domains.first())
            .map(|domain| domain.trim_end_matches('.').to_string())
            .unwrap_or_default()
    }
}

/// A compiled rule plus the PTR entries it contributes.
struct Compiled {
    domain: String,
    rule: CompiledRule,
    ptr: Vec<(IpKey, String)>,
}

fn compile_rule(
    rule: &RuleConfig,
    default_ttl: u32,
    warnings: &mut Vec<String>,
) -> Option<Compiled> {
    let domain = normalize_domain(&rule.domain);
    if domain.is_empty() {
        return None;
    }
    let ttl = if rule.ttl == 0 { default_ttl } else { rule.ttl };
    let records = compile_records(&domain, &rule.records, warnings);
    let rcode = if rule.rcode.is_empty() {
        RCODE_SUCCESS
    } else {
        match parse_rcode(&rule.rcode) {
            Some(code) => code,
            None => {
                warnings.push(format!(
                    "规则 {} 的应答码 {:?} 无法识别，按 NOERROR 处理",
                    domain, rule.rcode
                ));
                RCODE_SUCCESS
            }
        }
    };

    let is_wildcard = domain.starts_with("*.");
    let suffix = if is_wildcard {
        domain[2..].to_string()
    } else {
        String::new()
    };

    let cname = if rule.cname.is_empty() {
        String::new()
    } else {
        let mut cname = go_trim_space(&rule.cname).to_string();
        if !cname.ends_with('.') {
            cname.push('.');
        }
        cname
    };

    let mut v4 = Vec::new();
    let mut v6 = Vec::new();
    let mut ptr = Vec::new();
    for raw in &rule.ips {
        let Some(key) = ip_key_text(go_trim_space(raw)) else {
            continue;
        };
        match key {
            IpKey::V4(address) => {
                v4.push(address);
                if !is_wildcard {
                    ptr.push((key, format!("{domain}.")));
                }
            }
            IpKey::V6(address) => {
                v6.push(address);
                if !is_wildcard {
                    ptr.push((key, format!("{domain}.")));
                }
            }
        }
    }

    Some(Compiled {
        domain,
        rule: CompiledRule {
            is_wildcard,
            suffix,
            v4,
            v6,
            cname,
            txt: rule.txt.clone(),
            ttl,
            records,
            rcode,
        },
        ptr,
    })
}

/// Validates explicit records and keeps the legal ones, reporting the rest exactly once — the old
/// `compileRewriteRecords` ran this at rule build time so a bad value never reached a query.
fn compile_records(domain: &str, specs: &[RecordSpec], warnings: &mut Vec<String>) -> Vec<Record> {
    let mut kept = Vec::with_capacity(specs.len());
    for spec in specs {
        if go_trim_space(&spec.type_name).is_empty() {
            continue;
        }
        let upper = go_upper(go_trim_space(&spec.type_name));
        if dns_type::string_to_type(&upper).is_none() {
            warnings.push(format!(
                "规则 {} 的记录类型 {:?} 不受支持，已忽略",
                domain, spec.type_name
            ));
            continue;
        }
        // The probe name and TTL only serve validation; the query name and rule TTL are applied
        // when the compiled body is answered.
        let Some(rrtype) = record::type_number(&spec.type_name) else {
            warnings.push(format!(
                "规则 {} 的 {} 记录取值非法（不支持的记录类型 {:?}），已忽略",
                domain, spec.type_name, spec.type_name
            ));
            continue;
        };
        match record::build(
            "probe.invalid.",
            rrtype,
            &spec.type_name,
            &spec.value,
            DEFAULT_TTL,
        ) {
            Ok(Some(parsed)) => kept.push(parsed.record),
            Ok(None) => {}
            Err(error) => warnings.push(format!(
                "规则 {} 的 {} 记录取值非法（{}），已忽略",
                domain, spec.type_name, error
            )),
        }
    }
    kept
}

fn answer(owner: &str, ttl: u32, record: Record) -> Answer {
    Answer {
        owner: owner.to_string(),
        ttl,
        record,
    }
}

/// `normalizeRewriteDomain`: lowercase, trim whitespace, then trim leading/trailing dots.
pub fn normalize_domain(domain: &str) -> String {
    go_trim_space(&go_lower(domain))
        .trim_matches('.')
        .to_string()
}

/// The query owner: Go appended a dot with `strings.HasSuffix`, not with the escape-aware
/// `dns.Fqdn`. Domain names cannot end in an escaped dot in practice, but the rule is cheap to keep.
fn query_fqdn(domain: &str) -> String {
    if domain.ends_with('.') {
        domain.to_string()
    } else {
        format!("{domain}.")
    }
}

/// `ParseRewriteRCode` over the same six names; also the `$dnsrewrite` keyword table.
pub(crate) fn parse_rcode(name: &str) -> Option<u16> {
    let upper = go_upper(go_trim_space(name));
    match upper.as_ref() {
        "NOERROR" => Some(0),
        "FORMERR" => Some(1),
        "SERVFAIL" => Some(2),
        "NXDOMAIN" => Some(3),
        "NOTIMP" => Some(4),
        "REFUSED" => Some(5),
        _ => None,
    }
}

/// `net.ParseIP` + `To4`: an IPv4 literal or an IPv4-mapped IPv6 literal is a V4 key.
fn ip_key_text(value: &str) -> Option<IpKey> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(IpKey::V4(address.octets()));
    }
    let octets = value.parse::<Ipv6Addr>().ok()?.octets();
    Some(ip_key_octets(octets))
}

/// Go passes already-canonicalized address bytes (`To4` applied); a 4-byte slice is V4, a 16-byte
/// slice is V6 unless it is the mapped form the build pass would have collapsed.
fn ip_key_bytes(bytes: &[u8]) -> Option<IpKey> {
    match bytes.len() {
        4 => {
            let mut address = [0u8; 4];
            address.copy_from_slice(bytes);
            Some(IpKey::V4(address))
        }
        16 => {
            let mut octets = [0u8; 16];
            octets.copy_from_slice(bytes);
            Some(ip_key_octets(octets))
        }
        _ => None,
    }
}

fn ip_key_octets(octets: [u8; 16]) -> IpKey {
    match mapped_ipv4(octets) {
        Some(address) => IpKey::V4(address),
        None => IpKey::V6(octets),
    }
}

/// RFC 1034 §3.6.2: when a name answers with a CNAME, no other record may share that owner.
fn merge_owner_cname(answers: Vec<Answer>) -> Vec<Answer> {
    let mut owners: Vec<String> = Vec::new();
    for answer in &answers {
        if answer.record.rrtype() == TYPE_CNAME {
            let owner = go_lower(&answer.owner).into_owned();
            if !owners.contains(&owner) {
                owners.push(owner);
            }
        }
    }
    if owners.is_empty() {
        return answers;
    }
    answers
        .into_iter()
        .filter(|answer| {
            !(owners.contains(&go_lower(&answer.owner).into_owned())
                && answer.record.rrtype() != TYPE_CNAME)
        })
        .collect()
}

#[cfg(test)]
mod tests;

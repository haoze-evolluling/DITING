use std::collections::HashMap;
use std::net::{Ipv4Addr, Ipv6Addr};

use diting_go_compat::dns_type;
use diting_go_compat::text::{go_lower, go_trim_space, go_upper};

use crate::record::{self, mapped_ipv4, Record, TYPE_A, TYPE_AAAA, TYPE_CNAME, TYPE_TXT};

pub const DEFAULT_TTL: u32 = 60;

const RCODE_SUCCESS: u16 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecordSpec {
    pub type_name: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleConfig {
    pub domain: String,
    pub ips: Vec<String>,
    pub cname: String,
    pub txt: Vec<String>,
    pub ttl: u32,
    pub records: Vec<RecordSpec>,
    pub rcode: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub enabled: bool,
    pub default_ttl: u32,
    pub rules: Vec<RuleConfig>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Answer {
    pub owner: String,
    pub ttl: u32,
    pub record: Record,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LookupResult {
    pub matched: bool,
    pub rcode: u16,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum IpKey {
    V4([u8; 4]),
    V6([u8; 16]),
}

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

pub struct Engine {
    enabled: bool,
    default_ttl: u32,
    exact: HashMap<String, CompiledRule>,
    wildcard: Vec<CompiledRule>,
    ptr: HashMap<IpKey, Vec<String>>,
}

impl Engine {
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
        engine
            .wildcard
            .sort_by_key(|rule| std::cmp::Reverse(rule.suffix.len()));
        (engine, warnings)
    }

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
            self.exact.insert(compiled.domain, compiled.rule);
        }
    }

    pub fn enabled(&self) -> bool {
        self.enabled
    }

    pub fn default_ttl(&self) -> u32 {
        self.default_ttl
    }

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

    pub fn lookup_ptr(&self, ip: &[u8]) -> Vec<String> {
        if !self.enabled {
            return Vec::new();
        }
        let Some(key) = ip_key_bytes(ip) else {
            return Vec::new();
        };
        self.ptr.get(&key).cloned().unwrap_or_default()
    }

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

pub fn normalize_domain(domain: &str) -> String {
    go_trim_space(&go_lower(domain))
        .trim_matches('.')
        .to_string()
}

fn query_fqdn(domain: &str) -> String {
    if domain.ends_with('.') {
        domain.to_string()
    } else {
        format!("{domain}.")
    }
}

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

fn ip_key_text(value: &str) -> Option<IpKey> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(IpKey::V4(address.octets()));
    }
    let octets = value.parse::<Ipv6Addr>().ok()?.octets();
    Some(ip_key_octets(octets))
}

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

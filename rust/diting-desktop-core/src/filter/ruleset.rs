//! Rule parsing, source selection and the compiled matcher.
//!
//! Rule *semantics* stay in `diting-filter-core`; this module is the bridge the Go engine used to
//! be: it reads custom rules and subscription cache files through the kernel parser, expands the
//! built-in service catalog, compiles the regexes/wildcards, and turns a kernel [`Decision`] back
//! into a [`CheckHostResult`] using the side table of raw rule text and source names.

use std::collections::HashSet;
use std::fs;
use std::path::Path;

use diting_filter_core::parse::{parse_document, parse_line, ParsedLine};
use diting_filter_core::rule::{
    Rule, FLAG_ALLOW, FLAG_EXACT, FLAG_IMPORTANT, FLAG_REGEX, FLAG_REWRITE, FLAG_WILDCARD,
};
use diting_filter_core::{Action, Decision, FilterIndex, Reason, RewriteAnswer};
use diting_go_compat::regex::compile_rule_regex;
use diting_rewrite_core::action::Action as RewriteAction;
use diting_rewrite_core::record::{self, Record, SvcParam};
use diting_services_core::catalog::{Service, CATALOG, CATEGORIES};
use regex::Regex;

use crate::filter::types::{
    CheckHostResult, RewriteRecord, RewriteResult, VerdictAction, REASON_ALLOWLIST_ONLY,
    REASON_BLACKLIST, REASON_DNSREWRITE, REASON_IMPORTANT_ALLOW, REASON_IMPORTANT_BLOCK,
    REASON_REGEX_BLOCK, REASON_WHITELIST, REASON_WILDCARD_BLOCK, REWRITE_TTL,
};

/// Source prefix for built-in service rules (`service:<id>`).
pub(crate) const SERVICE_SOURCE_PREFIX: &str = "service:";
/// Source name for user-defined rules.
pub(crate) const CUSTOM_SOURCE: &str = "custom";

/// One parsed rule plus the two strings the query log needs.
#[derive(Debug, Clone)]
pub(crate) struct CompiledRule {
    pub(crate) kernel: Rule,
    pub(crate) raw: String,
    pub(crate) source: String,
    /// The full `$dnsrewrite` action (the kernel rule only needs its key and shape).
    pub(crate) rewrite: Option<RewriteAction>,
}

/// The rules of one build, kept per source class so groups can select list rules only.
#[derive(Debug, Clone, Default)]
pub(crate) struct RuleSet {
    pub(crate) custom: Vec<CompiledRule>,
    pub(crate) service: Vec<CompiledRule>,
    pub(crate) lists: Vec<CompiledRule>,
}

impl RuleSet {
    /// Global priority order: custom → built-in services → subscription lists (declaration order).
    pub(crate) fn all(&self) -> Vec<&CompiledRule> {
        self.custom
            .iter()
            .chain(self.service.iter())
            .chain(self.lists.iter())
            .collect()
    }

    /// Group selection: custom/service are always included; an empty id list inherits every list.
    pub(crate) fn for_group(&self, list_ids: &[String]) -> Vec<&CompiledRule> {
        let mut selected: Vec<&CompiledRule> = Vec::new();
        selected.extend(self.custom.iter());
        selected.extend(self.service.iter());
        if list_ids.is_empty() {
            selected.extend(self.lists.iter());
        } else {
            let allow: HashSet<&str> = list_ids.iter().map(String::as_str).collect();
            selected.extend(
                self.lists
                    .iter()
                    .filter(|rule| allow.contains(rule.source.as_str())),
            );
        }
        selected
    }
}

/// The built matcher: the kernel index plus its rule side table.
pub(crate) struct RuleMatcher {
    index: FilterIndex,
    entries: Vec<CompiledRule>,
}

impl RuleMatcher {
    /// Builds an immutable index over the given rules, in order.
    pub(crate) fn build(rules: impl IntoIterator<Item = CompiledRule>) -> Self {
        let entries: Vec<CompiledRule> = rules.into_iter().collect();
        let kernel: Vec<Rule> = entries.iter().map(|rule| rule.kernel.clone()).collect();
        Self {
            index: FilterIndex::build(kernel),
            entries,
        }
    }

    pub(crate) fn total_rules(&self) -> u32 {
        self.index.total_rules()
    }

    /// Evaluates one normalized domain and translates the kernel decision.
    pub(crate) fn match_domain(&self, domain: &str, qtype: u16) -> CheckHostResult {
        let decision = self.index.match_domain(domain, qtype);
        self.to_result(decision, domain, qtype)
    }

    fn to_result(&self, decision: Decision, domain: &str, qtype: u16) -> CheckHostResult {
        let entry = decision
            .rule
            .and_then(|index| self.entries.get(index as usize));

        if decision.action == Action::Rewrite {
            let answer = decision.rewrite.unwrap_or(RewriteAnswer {
                rcode: 0,
                rules: Vec::new(),
            });
            return CheckHostResult {
                blocked: false,
                action: VerdictAction::Rewrite,
                matched_rule: entry.map(|rule| rule.raw.clone()).unwrap_or_default(),
                list_name: entry.map(|rule| rule.source.clone()).unwrap_or_default(),
                reason: REASON_DNSREWRITE.to_string(),
                rewritten: Some(self.build_rewrite(&answer, domain, qtype)),
            };
        }

        let action = match decision.action {
            Action::Allow => VerdictAction::Allow,
            Action::Block => VerdictAction::Block,
            Action::Pass | Action::Rewrite => VerdictAction::Pass,
        };
        CheckHostResult {
            blocked: action == VerdictAction::Block,
            action,
            matched_rule: entry.map(|rule| rule.raw.clone()).unwrap_or_default(),
            list_name: entry.map(|rule| rule.source.clone()).unwrap_or_default(),
            reason: decision
                .reason
                .map(reason_name)
                .unwrap_or_default()
                .to_string(),
            rewritten: None,
        }
    }

    /// `rewriteRecords`: every winning rule's value becomes one record, in kernel order.
    fn build_rewrite(&self, answer: &RewriteAnswer, domain: &str, qtype: u16) -> RewriteResult {
        let mut result = RewriteResult {
            rcode: answer.rcode,
            records: Vec::new(),
            summary: Vec::new(),
        };
        if answer.rcode != 0 {
            return result;
        }
        for index in &answer.rules {
            let Some(action) = self
                .entries
                .get(*index as usize)
                .and_then(|rule| rule.rewrite.as_ref())
            else {
                continue;
            };
            if action.bare || action.rcode != 0 || action.rrtype == 0 {
                continue;
            }
            let Some(type_name) = record_type_name(action.rrtype) else {
                continue;
            };
            let Ok(Some(parsed)) =
                record::build(domain, qtype, type_name, &action.value, REWRITE_TTL)
            else {
                continue;
            };
            let value = record_value(&parsed.record);
            result.summary.push(format!(
                "{} {} IN {} {}",
                parsed.owner, parsed.ttl, type_name, value
            ));
            result.records.push(RewriteRecord {
                kind: type_name.to_string(),
                value,
                ttl: parsed.ttl,
            });
        }
        result
    }
}

/// Loads custom rules through the single-line parser (Go's `ParseRuleLine`).
pub(crate) fn parse_custom_rules(lines: &[String]) -> Vec<CompiledRule> {
    lines
        .iter()
        .filter_map(|line| parse_line(line))
        .filter_map(|parsed| compile_line(parsed, CUSTOM_SOURCE))
        .collect()
}

/// Loads one subscription cache file; a missing/unreadable file contributes no rules.
pub(crate) fn parse_list_file(data_dir: &Path, list_id: &str) -> Vec<CompiledRule> {
    let path = data_dir.join(format!("{list_id}.txt"));
    let Ok(data) = fs::read(path) else {
        return Vec::new();
    };
    let text = String::from_utf8_lossy(&data);
    parse_list_text(&text, list_id)
}

/// Loads a document held in memory (used by refresh to count rules before writing).
pub(crate) fn parse_list_text(text: &str, source: &str) -> Vec<CompiledRule> {
    parse_document(text)
        .into_iter()
        .filter_map(|parsed| compile_line(parsed, source))
        .collect()
}

/// Expands selected built-in services and groups into block rules.
///
/// Unknown ids are skipped; a service selected both directly and through its group expands once.
pub(crate) fn expand_services(service_ids: &[String], group_ids: &[String]) -> Vec<CompiledRule> {
    if service_ids.is_empty() && group_ids.is_empty() {
        return Vec::new();
    }
    let selected: HashSet<&str> = service_ids.iter().map(|id| id.trim()).collect();
    let groups: HashSet<&str> = group_ids.iter().map(|id| id.trim()).collect();

    let mut out = Vec::new();
    for service in CATALOG {
        if !selected.contains(service.id) && !groups.contains(service.category) {
            continue;
        }
        out.extend(expand_service(service));
    }
    out
}

/// Whether a service group token exists in the catalog.
pub(crate) fn service_group_exists(id: &str) -> bool {
    CATEGORIES.contains(&id.trim())
}

/// Whether a service id exists in the catalog.
pub(crate) fn service_exists(id: &str) -> bool {
    diting_services_core::catalog::find(id.trim()).is_some()
}

/// `CountBlockedServiceRules`: deduplicated service/group union.
pub(crate) fn count_service_rules(service_ids: &[String], group_ids: &[String]) -> usize {
    expand_services(service_ids, group_ids).len()
}

fn expand_service(service: &'static Service) -> Vec<CompiledRule> {
    let source = format!("{SERVICE_SOURCE_PREFIX}{}", service.id);
    service
        .domains
        .iter()
        .filter_map(|domain| parse_line(&format!("||{domain}^")))
        .filter_map(|parsed| compile_line(parsed, &source))
        .collect()
}

/// Turns one parsed line into a kernel rule, dropping the same cases Go dropped.
fn compile_line(parsed: ParsedLine, source: &str) -> Option<CompiledRule> {
    let mut flags = 0u8;
    if parsed.is_allow {
        flags |= FLAG_ALLOW;
    }
    if parsed.important {
        flags |= FLAG_IMPORTANT;
    }
    if parsed.is_regex {
        flags |= FLAG_REGEX;
    }
    if parsed.is_wildcard {
        flags |= FLAG_WILDCARD;
    }
    if parsed.is_exact {
        flags |= FLAG_EXACT;
    }
    if parsed.rewrite.is_some() {
        flags |= FLAG_REWRITE;
    }

    let compiled_regex = if parsed.is_regex {
        // Go drops an uncompilable `/regex/` rule outright.
        Some(compile_rule_regex(&parsed.pattern).ok()?)
    } else if parsed.is_wildcard {
        // Go keeps a wildcard rule with a nil regex (it simply never matches).
        build_wildcard_regex(&parsed.pattern)
    } else {
        None
    };

    let rewrite = match parsed.rewrite.as_deref() {
        None => None,
        // An unparsable `$dnsrewrite` value drops the whole rule, like Go did.
        Some(raw) => Some(RewriteAction::parse(raw).ok()?),
    };

    let kernel_rewrite = rewrite
        .as_ref()
        .map(|action| diting_filter_core::rule::RewriteAction {
            bare: action.bare,
            rcode: action.rcode.min(u8::MAX as u16) as u8,
            rrtype: action.rrtype,
            key: action.key(),
        });

    Some(CompiledRule {
        kernel: Rule {
            pattern: parsed.pattern,
            regex: compiled_regex,
            flags,
            dns_type: parsed.dns_type,
            deny_allow: parsed.deny_allow,
            to: parsed.to,
            rewrite: kernel_rewrite,
        },
        raw: parsed.raw,
        source: source.to_string(),
        rewrite,
    })
}

/// `buildWildcardRegex`: optional sub-domain prefix, `*` → `.*`, case-insensitive.
fn build_wildcard_regex(pattern: &str) -> Option<Regex> {
    let mut source = String::from("^(?:.*\\.)?");
    for character in pattern.chars() {
        if character == '*' {
            source.push_str(".*");
        } else {
            source.push_str(&regex::escape(&character.to_string()));
        }
    }
    source.push('$');
    compile_rule_regex(&source).ok()
}

fn reason_name(reason: Reason) -> &'static str {
    match reason {
        Reason::ImportantAllow => REASON_IMPORTANT_ALLOW,
        Reason::ImportantBlock => REASON_IMPORTANT_BLOCK,
        Reason::Whitelist => REASON_WHITELIST,
        Reason::Blacklist => REASON_BLACKLIST,
        Reason::WildcardBlock => REASON_WILDCARD_BLOCK,
        Reason::RegexBlock => REASON_REGEX_BLOCK,
    }
}

/// Applies allowlist-only mode: only an allow/rewrite result survives.
pub(crate) fn apply_allowlist_only(mut result: CheckHostResult) -> CheckHostResult {
    if result.blocked || result.action == VerdictAction::Allow || result.is_rewrite() {
        return result;
    }
    result.blocked = true;
    result.action = VerdictAction::Block;
    result.reason = REASON_ALLOWLIST_ONLY.to_string();
    result.matched_rule.clear();
    result.list_name.clear();
    result
}

fn record_type_name(rrtype: u16) -> Option<&'static str> {
    Some(match rrtype {
        1 => "A",
        2 => "NS",
        5 => "CNAME",
        12 => "PTR",
        15 => "MX",
        16 => "TXT",
        28 => "AAAA",
        33 => "SRV",
        64 => "SVCB",
        65 => "HTTPS",
        _ => return None,
    })
}

/// Formats a typed record back into the API's `type/value` shape.
fn record_value(record: &Record) -> String {
    match record {
        Record::A(bytes) => std::net::Ipv4Addr::from(*bytes).to_string(),
        Record::Aaaa(bytes) => std::net::Ipv6Addr::from(*bytes).to_string(),
        Record::Cname(name) | Record::Ns(name) | Record::Ptr(name) => trim_target(name).to_string(),
        Record::Txt(strings) => strings.join(" "),
        Record::Mx {
            preference,
            exchange,
        } => format!("{preference} {}", trim_target(exchange)),
        Record::Srv {
            priority,
            weight,
            port,
            target,
        } => format!("{priority} {weight} {port} {}", trim_target(target)),
        Record::Svcb {
            priority,
            target,
            params,
            ..
        } => {
            let mut value = format!("{priority} {}", trim_target(target));
            for param in params {
                value.push(' ');
                value.push_str(&svc_param_text(param));
            }
            value
        }
    }
}

fn svc_param_text(param: &SvcParam) -> String {
    match param {
        SvcParam::Mandatory(keys) => format!(
            "mandatory={}",
            keys.iter()
                .map(|key| svc_key_name(*key))
                .collect::<Vec<_>>()
                .join(",")
        ),
        SvcParam::Alpn(protocols) => format!("alpn={}", protocols.join(",")),
        SvcParam::NoDefaultAlpn => "no-default-alpn".to_string(),
        SvcParam::Port(port) => format!("port={port}"),
        SvcParam::Ipv4Hint(addresses) => format!(
            "ipv4hint={}",
            addresses
                .iter()
                .map(|bytes| std::net::Ipv4Addr::from(*bytes).to_string())
                .collect::<Vec<_>>()
                .join(",")
        ),
        SvcParam::Ech(bytes) => {
            use base64::Engine as _;
            format!(
                "ech={}",
                base64::engine::general_purpose::STANDARD.encode(bytes)
            )
        }
        SvcParam::Ipv6Hint(addresses) => format!(
            "ipv6hint={}",
            addresses
                .iter()
                .map(|bytes| std::net::Ipv6Addr::from(*bytes).to_string())
                .collect::<Vec<_>>()
                .join(",")
        ),
        SvcParam::DoHPath(path) => format!("dohpath={path}"),
    }
}

/// Presentation form of a record target: keep the root `.`, drop one trailing dot otherwise.
fn trim_target(name: &str) -> &str {
    if name == "." {
        "."
    } else {
        name.trim_end_matches('.')
    }
}

fn svc_key_name(key: u16) -> &'static str {
    match key {
        0 => "mandatory",
        1 => "alpn",
        2 => "no-default-alpn",
        3 => "port",
        4 => "ipv4hint",
        5 => "ech",
        6 => "ipv6hint",
        7 => "dohpath",
        _ => "ohttp",
    }
}

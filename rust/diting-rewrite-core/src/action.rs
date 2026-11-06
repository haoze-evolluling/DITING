//! `$dnsrewrite` value parsing and the normalized action key.
//!
//! This is the old Go `parseDNSRewriteModifier` + `parseShorthandRewrite` + `RewriteAction.key()`,
//! moved here so the modifier cannot mean one thing in the rule parser and another in the matcher.
//!
//! ```text
//! $dnsrewrite=1.2.3.4                   shorthand -> NOERROR;A;1.2.3.4
//! $dnsrewrite=abcd::1234                shorthand -> NOERROR;AAAA;abcd::1234
//! $dnsrewrite=example.net               shorthand -> NOERROR;CNAME;example.net
//! $dnsrewrite=REFUSED                   rcode only, no record
//! $dnsrewrite=NOERROR;TXT;hello_world   explicit RCODE;TYPE;VALUE
//! $dnsrewrite=NOERROR;;                 authoritative NODATA
//! $dnsrewrite                           bare form, exceptions only
//! ```
//!
//! The value itself is validated through [`crate::record::build`], the same entry point a
//! configured rewrite rule uses, so "the parser accepts it but the builder refuses it" cannot
//! happen — the accepted set is one set.
//!
//! Go keeps the `RewriteAction` struct (the rule index payload carries its fields), the `dns.RR`
//! construction and the display text. Everything that decides *what the text means* is here.

use std::net::{Ipv4Addr, Ipv6Addr};

use diting_go_compat::dns_type::string_to_type;
use diting_go_compat::text::{go_lower, go_trim_space, go_upper};

use crate::engine::{parse_rcode, DEFAULT_TTL};
use crate::record::{self, mapped_ipv4, TYPE_A, TYPE_AAAA, TYPE_CNAME, TYPE_NS, TYPE_PTR};

/// `dns.RcodeSuccess`.
pub const RCODE_SUCCESS: u16 = 0;

/// One parsed `$dnsrewrite` modifier.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Action {
    /// Bare `$dnsrewrite` (no value): an exception that cancels every rewrite of the name.
    pub bare: bool,
    /// Answer code; meaningless when [`Action::bare`] is set.
    pub rcode: u16,
    /// Record type; `0` means the action answers without records (NODATA or a failure code).
    pub rrtype: u16,
    /// Record value as written in the rule: trimmed, otherwise untouched (`TXT` keeps its case).
    pub value: String,
}

impl Action {
    fn new(bare: bool, rcode: u16, rrtype: u16, value: &str) -> Self {
        Self {
            bare,
            rcode,
            rrtype,
            value: value.to_string(),
        }
    }

    /// Parses the text after `$dnsrewrite=`, case preserved.
    ///
    /// An empty value is the bare form. A rejection is the message the Go caller logs before it
    /// drops the whole rule, exactly like an uncompilable regular expression.
    pub fn parse(text: &str) -> Result<Self, String> {
        let trimmed = go_trim_space(text);
        if trimmed.is_empty() {
            return Ok(Self::new(true, RCODE_SUCCESS, 0, ""));
        }

        // `RCODE;TYPE;VALUE`: only the first two separators are split, the value may contain more.
        let mut parts = trimmed.splitn(3, ';');
        let first = parts.next().unwrap_or("");
        let Some(second) = parts.next() else {
            return parse_shorthand(trimmed);
        };
        let third = parts.next();

        let rcode = parse_rcode(first).ok_or_else(|| format!("未知的应答码 {first:?}"))?;
        if rcode != RCODE_SUCCESS {
            // On a failure code the type and value are ignored (`REFUSED;;` is legal).
            return Ok(Self::new(false, rcode, 0, ""));
        }

        let type_name = go_trim_space(second);
        let value = third.map(go_trim_space).unwrap_or("");
        if type_name.is_empty() {
            // `NOERROR;;` — the name explicitly has no records.
            return Ok(Self::new(false, RCODE_SUCCESS, 0, ""));
        }

        let rrtype = string_to_type(go_upper(type_name).as_ref())
            .ok_or_else(|| format!("未知的记录类型 {type_name:?}"))?;
        validate(type_name, rrtype, value)?;
        Ok(Self::new(false, RCODE_SUCCESS, rrtype, value))
    }

    /// The normalized key a cancelling exception is compared by.
    ///
    /// Two spellings of the same target (`127.0.0.1` / `::ffff:127.0.0.1`, `Example.ORG.` /
    /// `example.org`) must produce the same key, otherwise `@@||x^$dnsrewrite=...` would silently
    /// fail to cancel the rule it describes. The comparison happens inside the rule index, so the
    /// normalization lives with the parser rather than in the caller.
    pub fn key(&self) -> String {
        if self.bare {
            return "bare".to_string();
        }
        format!(
            "{};{};{}",
            self.rcode,
            self.rrtype,
            normalize_value(self.rrtype, &self.value)
        )
    }
}

/// The shorthand form: an rcode keyword, an IP literal, or a CNAME target.
fn parse_shorthand(value: &str) -> Result<Action, String> {
    if let Some(rcode) = parse_rcode(value) {
        return Ok(Action::new(false, rcode, 0, ""));
    }

    match ip_family(value) {
        // Both literals keep their original spelling: the record builder parses them again, and a
        // rewritten answer should show what the rule wrote.
        Some(Family::V4) => Ok(Action::new(false, RCODE_SUCCESS, TYPE_A, value)),
        Some(Family::V6) => Ok(Action::new(false, RCODE_SUCCESS, TYPE_AAAA, value)),
        None => {
            validate("CNAME", TYPE_CNAME, value)?;
            Ok(Action::new(false, RCODE_SUCCESS, TYPE_CNAME, value))
        }
    }
}

/// Address family of a shorthand value, with Go's `net.ParseIP` + `To4` split: an IPv4-mapped
/// IPv6 literal counts as IPv4.
enum Family {
    V4,
    V6,
}

fn ip_family(value: &str) -> Option<Family> {
    if value.parse::<Ipv4Addr>().is_ok() {
        return Some(Family::V4);
    }
    let octets = value.parse::<Ipv6Addr>().ok()?.octets();
    Some(match mapped_ipv4(octets) {
        Some(_) => Family::V4,
        None => Family::V6,
    })
}

/// Validates a value against its record type through the record builder.
///
/// `rrtype` is passed as the query type so a type mismatch cannot end the build early with "no
/// record": that would accept values the builder cannot actually turn into a record.
fn validate(type_name: &str, rrtype: u16, value: &str) -> Result<(), String> {
    let canonical = go_upper(go_trim_space(type_name));
    if go_trim_space(value).is_empty() {
        return Err(format!("{canonical} 记录缺少取值"));
    }
    match record::build("probe.invalid.", rrtype, type_name, value, DEFAULT_TTL) {
        Ok(Some(_)) => Ok(()),
        Ok(None) => Err(format!("{canonical} 记录的取值 {value:?} 无法解析")),
        Err(error) => Err(error),
    }
}

/// The value as the key sees it: canonical address text, lowercased target without its trailing
/// dot, and only trimmed for everything else.
fn normalize_value(rrtype: u16, value: &str) -> String {
    let trimmed = go_trim_space(value);
    match rrtype {
        TYPE_A | TYPE_AAAA => canonical_ip(trimmed).unwrap_or_else(|| trimmed.to_string()),
        TYPE_CNAME | TYPE_PTR | TYPE_NS => {
            let lowered = go_lower(trimmed);
            lowered
                .strip_suffix('.')
                .unwrap_or(lowered.as_ref())
                .to_string()
        }
        _ => trimmed.to_string(),
    }
}

/// `net.ParseIP(...).String()`: an IPv4-mapped literal prints as plain IPv4, like Go's `To4`.
fn canonical_ip(value: &str) -> Option<String> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(address.to_string());
    }
    let octets = value.parse::<Ipv6Addr>().ok()?.octets();
    Some(match mapped_ipv4(octets) {
        Some(address) => Ipv4Addr::from(address).to_string(),
        None => Ipv6Addr::from(octets).to_string(),
    })
}

#[cfg(test)]
mod tests;

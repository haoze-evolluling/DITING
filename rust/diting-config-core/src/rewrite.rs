//! The per-domain rewrite table: target classification and key normalization.
//!
//! `SetRewriteRules` took a JSON object of `domain -> target(s)` and turned each value into at most
//! one IPv4 answer, one IPv6 answer and one CNAME target — in that order per target, first one wins,
//! blank targets skipped, non-IP targets lower-cased and stripped of a trailing dot. Every lookup key
//! (the table's own keys, the query domain, the diagnostics path) went through the same
//! `TrimSuffix(ToLower(TrimSpace(domain)), ".")` fold, which is why it lives here next to the table.

use diting_go_compat::ip::{go_ip_string, to4};
use diting_go_compat::netaddr::parse_ip;
use diting_go_compat::text::{go_lower_trim_dot, go_trim_space};

/// One rewrite target set, already normalized.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Entry {
    /// The CNAME target, lower-case and without a trailing dot.
    pub cname: String,
    /// The IPv4 answer in `net.IP.String()` form.
    pub ip4: String,
    /// The IPv6 answer in `net.IP.String()` form.
    pub ip6: String,
}

impl Entry {
    /// True when nothing survived, i.e. `parseRewriteEntry` returned `nil` and the value is dropped.
    pub fn is_empty(&self) -> bool {
        self.cname.is_empty() && self.ip4.is_empty() && self.ip6.is_empty()
    }
}

/// `parseRewriteEntry`: classify the decoded target list.
///
/// A JSON string and a JSON array both arrive here as their effective target list (Go does the
/// string-vs-array dispatch), so this is the whole classification rule.
pub fn classify(targets: &[String]) -> Option<Entry> {
    let mut entry = Entry::default();
    let mut has_ip4 = false;
    let mut has_ip6 = false;
    for target in targets {
        let target = go_trim_space(target);
        if target.is_empty() {
            continue;
        }
        if let Some(bytes) = parse_ip(target) {
            // `net.IP.To4` is the IPv4 test; the text comes back through `net.IP.String()`, so a
            // mapped literal (`::ffff:1.2.3.4`) is stored in its dotted-quad form.
            if to4(&bytes).is_some() {
                if !has_ip4 {
                    entry.ip4 = go_ip_string(&bytes);
                    has_ip4 = true;
                }
            } else if !has_ip6 {
                entry.ip6 = go_ip_string(&bytes);
                has_ip6 = true;
            }
            continue;
        }
        if entry.cname.is_empty() {
            entry.cname = go_lower_trim_dot(target);
        }
    }
    if entry.is_empty() {
        return None;
    }
    Some(entry)
}

/// `TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")` — the lookup-key fold.
pub fn normalize_domain(domain: &str) -> String {
    go_lower_trim_dot(domain)
}

#[cfg(test)]
mod tests;

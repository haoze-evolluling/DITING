use std::borrow::Cow;

use diting_go_compat::ip::{go_ip_string, to4};
use diting_go_compat::netaddr::parse_ip;
use diting_go_compat::text::{
    go_lower_trim_dot, go_trim_space, normalize_domain as compat_normalize,
};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Entry {
    pub cname: String,
    pub ip4: String,
    pub ip6: String,
}

impl Entry {
    pub fn is_empty(&self) -> bool {
        self.cname.is_empty() && self.ip4.is_empty() && self.ip6.is_empty()
    }
}

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

pub fn normalize_domain(domain: &str) -> Cow<'_, str> {
    compat_normalize(domain)
}

#[cfg(test)]
mod tests;

use std::net::{Ipv4Addr, Ipv6Addr};

use diting_go_compat::dns_type::string_to_type;
use diting_go_compat::text::{go_lower, go_trim_space, go_upper};

use crate::engine::{parse_rcode, DEFAULT_TTL};
use crate::record::{self, mapped_ipv4, TYPE_A, TYPE_AAAA, TYPE_CNAME, TYPE_NS, TYPE_PTR};

pub const RCODE_SUCCESS: u16 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Action {
    pub bare: bool,
    pub rcode: u16,
    pub rrtype: u16,
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

    pub fn parse(text: &str) -> Result<Self, String> {
        let trimmed = go_trim_space(text);
        if trimmed.is_empty() {
            return Ok(Self::new(true, RCODE_SUCCESS, 0, ""));
        }

        let mut parts = trimmed.splitn(3, ';');
        let first = parts.next().unwrap_or("");
        let Some(second) = parts.next() else {
            return parse_shorthand(trimmed);
        };
        let third = parts.next();

        let rcode = parse_rcode(first).ok_or_else(|| format!("未知的应答码 {first:?}"))?;
        if rcode != RCODE_SUCCESS {
            return Ok(Self::new(false, rcode, 0, ""));
        }

        let type_name = go_trim_space(second);
        let value = third.map(go_trim_space).unwrap_or("");
        if type_name.is_empty() {
            return Ok(Self::new(false, RCODE_SUCCESS, 0, ""));
        }

        let rrtype = string_to_type(go_upper(type_name).as_ref())
            .ok_or_else(|| format!("未知的记录类型 {type_name:?}"))?;
        validate(type_name, rrtype, value)?;
        Ok(Self::new(false, RCODE_SUCCESS, rrtype, value))
    }

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

fn parse_shorthand(value: &str) -> Result<Action, String> {
    if let Some(rcode) = parse_rcode(value) {
        return Ok(Action::new(false, rcode, 0, ""));
    }

    match ip_family(value) {
        Some(Family::V4) => Ok(Action::new(false, RCODE_SUCCESS, TYPE_A, value)),
        Some(Family::V6) => Ok(Action::new(false, RCODE_SUCCESS, TYPE_AAAA, value)),
        None => {
            validate("CNAME", TYPE_CNAME, value)?;
            Ok(Action::new(false, RCODE_SUCCESS, TYPE_CNAME, value))
        }
    }
}

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

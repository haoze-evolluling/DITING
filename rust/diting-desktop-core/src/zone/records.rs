use std::net::{Ipv4Addr, Ipv6Addr};

pub const TYPE_A: u16 = 1;
pub const TYPE_NS: u16 = 2;
pub const TYPE_CNAME: u16 = 5;
pub const TYPE_SOA: u16 = 6;
pub const TYPE_PTR: u16 = 12;
pub const TYPE_MX: u16 = 15;
pub const TYPE_TXT: u16 = 16;
pub const TYPE_AAAA: u16 = 28;
pub const TYPE_SRV: u16 = 33;
pub const TYPE_CAA: u16 = 257;
pub const TYPE_ANY: u16 = 255;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ZoneRData {
    A(Ipv4Addr),
    Aaaa(Ipv6Addr),
    Cname(String),
    Ptr(String),
    Ns(String),
    Mx {
        preference: u16,
        exchange: String,
    },
    Txt(Vec<String>),
    Srv {
        priority: u16,
        weight: u16,
        port: u16,
        target: String,
    },
    Soa {
        mname: String,
        rname: String,
        serial: u32,
        refresh: u32,
        retry: u32,
        expire: u32,
        minimum: u32,
    },
    Caa {
        flags: u8,
        tag: String,
        value: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZoneRecord {
    pub owner: String,
    pub rtype: u16,
    pub ttl: u32,
    pub rdata: ZoneRData,
}

pub(crate) fn fqdn(name: &str) -> String {
    if name.is_empty() {
        ".".to_string()
    } else if name.ends_with('.') {
        name.to_string()
    } else {
        format!("{name}.")
    }
}

pub(crate) fn is_domain_name(name: &str) -> bool {
    if name == "." {
        return true;
    }
    let body = name.strip_suffix('.').unwrap_or(name);
    if body.is_empty() || body.len() > 253 {
        return false;
    }
    let mut total = 1;
    for label in body.split('.') {
        if label.is_empty() || label.len() > 63 {
            return false;
        }
        total += label.len() + 1;
        if label.bytes().any(|byte| byte <= 0x20 || byte == 0x7f) {
            return false;
        }
    }
    total <= 255
}

pub(crate) fn normalize_origin(raw: &str) -> Result<String, String> {
    let name = fqdn(&raw.trim().to_lowercase());
    if !is_domain_name(&name) {
        return Err(format!("区顶点 {raw:?} 不是合法域名"));
    }
    Ok(name)
}

pub(crate) fn resolve_name(token: &str, origin: &str) -> Result<String, String> {
    if token == "@" {
        return Ok(origin.to_string());
    }
    let lowered = token.to_lowercase();
    let name = if lowered == "." {
        ".".to_string()
    } else if lowered.ends_with('.') {
        lowered
    } else {
        format!("{}.{}", lowered, origin)
    };
    if !is_domain_name(&name) {
        return Err(format!("记录名 {token:?} 不是合法域名"));
    }
    Ok(name)
}

pub(crate) fn label_count(name: &str) -> usize {
    let body = name.strip_suffix('.').unwrap_or(name);
    if body.is_empty() {
        0
    } else {
        body.split('.').count()
    }
}

pub(crate) fn is_ttl_token(token: &str) -> bool {
    token
        .as_bytes()
        .first()
        .map(|byte| byte.is_ascii_digit())
        .unwrap_or(false)
}

pub(crate) fn parse_ttl(text: &str) -> Option<u32> {
    if text.is_empty() {
        return None;
    }
    if text.bytes().all(|byte| byte.is_ascii_digit()) {
        return text.parse::<u32>().ok();
    }
    let mut total: u64 = 0;
    let mut chars = text.chars().peekable();
    let mut parsed_any = false;
    while chars.peek().is_some() {
        let mut number = String::new();
        while let Some(character) = chars.peek() {
            if character.is_ascii_digit() {
                number.push(*character);
                chars.next();
            } else {
                break;
            }
        }
        if number.is_empty() {
            return None;
        }
        let value: u64 = number.parse().ok()?;
        let multiplier = match chars.next() {
            None => 1,
            Some(unit) => match unit.to_ascii_lowercase() {
                's' => 1,
                'm' => 60,
                'h' => 3_600,
                'd' => 86_400,
                'w' => 604_800,
                _ => return None,
            },
        };
        total = total.checked_add(value.checked_mul(multiplier)?)?;
        parsed_any = true;
    }
    if parsed_any {
        u32::try_from(total).ok()
    } else {
        None
    }
}

pub(crate) fn parse_u16(text: &str) -> Result<u16, String> {
    parse_unsigned(text)?
        .try_into()
        .map_err(|_| format!("{text:?} 不是 0-65535 之间的整数"))
}

pub(crate) fn parse_u8(text: &str) -> Result<u8, String> {
    parse_unsigned(text)?
        .try_into()
        .map_err(|_| format!("{text:?} 不是 0-255 之间的整数"))
}

pub(crate) fn parse_u32(text: &str) -> Result<u32, String> {
    parse_unsigned(text)?
        .try_into()
        .map_err(|_| format!("{text:?} 不是有效的 32 位整数"))
}

fn parse_unsigned(text: &str) -> Result<u64, String> {
    if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(format!("{text:?} 不是合法的无符号整数"));
    }
    text.parse::<u64>()
        .map_err(|_| format!("{text:?} 数值超出范围"))
}

pub(crate) fn record_type(token: &str) -> Option<u16> {
    match token.to_ascii_uppercase().as_str() {
        "A" => Some(TYPE_A),
        "NS" => Some(TYPE_NS),
        "CNAME" => Some(TYPE_CNAME),
        "SOA" => Some(TYPE_SOA),
        "PTR" => Some(TYPE_PTR),
        "MX" => Some(TYPE_MX),
        "TXT" => Some(TYPE_TXT),
        "AAAA" => Some(TYPE_AAAA),
        "SRV" => Some(TYPE_SRV),
        "CAA" => Some(TYPE_CAA),
        _ => None,
    }
}

pub(crate) fn is_class(token: &str) -> bool {
    matches!(
        token.to_ascii_uppercase().as_str(),
        "IN" | "CH" | "HS" | "NONE" | "ANY"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ttl_units() {
        assert_eq!(parse_ttl("300"), Some(300));
        assert_eq!(parse_ttl("1h"), Some(3_600));
        assert_eq!(parse_ttl("1h30m"), Some(5_400));
        assert_eq!(parse_ttl("1w"), Some(604_800));
        assert_eq!(parse_ttl("oops"), None);
    }

    #[test]
    fn domain_names() {
        assert!(is_domain_name("lan."));
        assert!(is_domain_name("_sip._tcp.lan."));
        assert!(!is_domain_name("bad..name."));
        assert!(!is_domain_name("bad name."));
        assert!(is_domain_name("."));
    }

    #[test]
    fn resolves_relative_names() {
        assert_eq!(resolve_name("@", "lan.").unwrap(), "lan.");
        assert_eq!(resolve_name("www", "lan.").unwrap(), "www.lan.");
        assert_eq!(resolve_name("WWW.Lan.", "lan.").unwrap(), "www.lan.");
        assert_eq!(resolve_name(".", "lan.").unwrap(), ".");
    }

    #[test]
    fn label_counts() {
        assert_eq!(label_count("lan."), 1);
        assert_eq!(label_count("www.lan."), 2);
        assert_eq!(label_count("."), 0);
    }
}

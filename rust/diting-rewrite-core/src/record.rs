//! `buildRewriteRR`: one configured rewrite record (type name + value text) turned into a typed
//! record.
//!
//! The value grammar is the one AdGuard Home's `$dnsrewrite` uses, and it is deliberately shared by
//! the two entry points that need it: the custom rewrite rules of the service
//! (`RewriteRule.Records`) and the `$dnsrewrite` rule modifier. Everything the old Go function
//! decided lives here — which types exist, how each value parses, which SVCB parameters are
//! accepted, what a legal target domain is — so Go has no second table and no second validation.
//!
//! Two Go behaviours are load-bearing and easy to get wrong:
//!
//! * a record is returned only when its type matches the query type, *except* CNAME, which is a
//!   property of the name and therefore eligible for every query;
//! * `is_rewrite_target` accepts single-label names (`nas`), because rewrite targets are often
//!   intranet hostnames, and rejects anything that parses as an IP address.

use std::net::{Ipv4Addr, Ipv6Addr};
use std::sync::OnceLock;

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine as _;
use diting_go_compat::text::{go_lower, go_trim_space, go_upper};
use idna::uts46::{AsciiDenyList, DnsLength, Hyphens, Uts46};

/// Record types the rewrite configuration understands.
pub const TYPE_A: u16 = 1;
/// NS records (`Records`).
pub const TYPE_NS: u16 = 2;
/// CNAME, the one type that answers every query type.
pub const TYPE_CNAME: u16 = 5;
/// PTR records (`Records`).
pub const TYPE_PTR: u16 = 12;
/// MX records (`Records`).
pub const TYPE_MX: u16 = 15;
/// TXT records.
pub const TYPE_TXT: u16 = 16;
/// AAAA records.
pub const TYPE_AAAA: u16 = 28;
/// SRV records (`Records`).
pub const TYPE_SRV: u16 = 33;
/// SVCB records (`Records`).
pub const TYPE_SVCB: u16 = 64;
/// HTTPS records (`Records`).
pub const TYPE_HTTPS: u16 = 65;

/// Type name → number. The old `rewriteRecordTypes` table, in the same order.
const RECORD_TYPES: [(&str, u16); 10] = [
    ("A", TYPE_A),
    ("AAAA", TYPE_AAAA),
    ("CNAME", TYPE_CNAME),
    ("TXT", TYPE_TXT),
    ("MX", TYPE_MX),
    ("SRV", TYPE_SRV),
    ("NS", TYPE_NS),
    ("PTR", TYPE_PTR),
    ("HTTPS", TYPE_HTTPS),
    ("SVCB", TYPE_SVCB),
];

/// The same names, sorted: this is the list `RewriteRecordTypes` returns for the UI dropdown.
const SORTED_TYPE_NAMES: [&str; 10] = [
    "A", "AAAA", "CNAME", "HTTPS", "MX", "NS", "PTR", "SRV", "SVCB", "TXT",
];

/// SVCB parameter keys (RFC 9460 §14.3.2), the values `svcbKeyByName` mapped to.
pub const SVCB_KEY_MANDATORY: u16 = 0;
/// `alpn`.
pub const SVCB_KEY_ALPN: u16 = 1;
/// `no-default-alpn`.
pub const SVCB_KEY_NO_DEFAULT_ALPN: u16 = 2;
/// `port`.
pub const SVCB_KEY_PORT: u16 = 3;
/// `ipv4hint`.
pub const SVCB_KEY_IPV4HINT: u16 = 4;
/// `ech`.
pub const SVCB_KEY_ECHCONFIG: u16 = 5;
/// `ipv6hint`.
pub const SVCB_KEY_IPV6HINT: u16 = 6;
/// `dohpath`.
pub const SVCB_KEY_DOHPATH: u16 = 7;

/// Parameter names `mandatory` may reference. `ohttp` is listed because the Go table listed it,
/// even though no parameter builder accepts it.
const SVCB_KEY_NAMES: [(&str, u16); 9] = [
    ("mandatory", SVCB_KEY_MANDATORY),
    ("alpn", SVCB_KEY_ALPN),
    ("no-default-alpn", SVCB_KEY_NO_DEFAULT_ALPN),
    ("port", SVCB_KEY_PORT),
    ("ipv4hint", SVCB_KEY_IPV4HINT),
    ("ech", SVCB_KEY_ECHCONFIG),
    ("ipv6hint", SVCB_KEY_IPV6HINT),
    ("dohpath", SVCB_KEY_DOHPATH),
    ("ohttp", 8),
];

/// One record body, with the type-specific fields already parsed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Record {
    /// A record: the four address bytes.
    A([u8; 4]),
    /// AAAA record: the sixteen address bytes.
    Aaaa([u8; 16]),
    /// CNAME target, a fully qualified name.
    Cname(String),
    /// NS target, a fully qualified name.
    Ns(String),
    /// PTR target, a fully qualified name.
    Ptr(String),
    /// TXT strings. A configured record holds one; the shortcut `TXT` field can hold several and
    /// still answers as a single TXT record.
    Txt(Vec<String>),
    /// MX preference and exchange, the exchange fully qualified.
    Mx {
        /// Preference.
        preference: u16,
        /// Exchange host, fully qualified.
        exchange: String,
    },
    /// SRV priority/weight/port and target, the target fully qualified.
    Srv {
        /// Priority.
        priority: u16,
        /// Weight.
        weight: u16,
        /// Port.
        port: u16,
        /// Target host, fully qualified.
        target: String,
    },
    /// SVCB or HTTPS: priority, target and the parameter list.
    Svcb {
        /// `true` for HTTPS (type 65), `false` for SVCB (type 64).
        https: bool,
        /// Priority; `0` means alias mode.
        priority: u16,
        /// Target name, fully qualified unless it is the root.
        target: String,
        /// Parameters in configuration order.
        params: Vec<SvcParam>,
    },
}

impl Record {
    /// The numeric record type this body answers as.
    pub fn rrtype(&self) -> u16 {
        match self {
            Record::A(_) => TYPE_A,
            Record::Aaaa(_) => TYPE_AAAA,
            Record::Cname(_) => TYPE_CNAME,
            Record::Ns(_) => TYPE_NS,
            Record::Ptr(_) => TYPE_PTR,
            Record::Txt(_) => TYPE_TXT,
            Record::Mx { .. } => TYPE_MX,
            Record::Srv { .. } => TYPE_SRV,
            Record::Svcb { https: true, .. } => TYPE_HTTPS,
            Record::Svcb { https: false, .. } => TYPE_SVCB,
        }
    }
}

/// One SVCB parameter, with its own key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SvcParam {
    /// `mandatory`: the referenced keys.
    Mandatory(Vec<u16>),
    /// `alpn`: the protocol list.
    Alpn(Vec<String>),
    /// `no-default-alpn`: no value.
    NoDefaultAlpn,
    /// `port`.
    Port(u16),
    /// `ipv4hint`: single address, as AdGuard Home's parser also allows only one.
    Ipv4Hint(Vec<[u8; 4]>),
    /// `ech`: the decoded config bytes.
    Ech(Vec<u8>),
    /// `ipv6hint`: single address.
    Ipv6Hint(Vec<[u8; 16]>),
    /// `dohpath`: the template.
    DoHPath(String),
}

impl SvcParam {
    /// The wire key (`SVCBKey` in Go), also used to reject duplicates.
    pub fn key(&self) -> u16 {
        match self {
            SvcParam::Mandatory(_) => SVCB_KEY_MANDATORY,
            SvcParam::Alpn(_) => SVCB_KEY_ALPN,
            SvcParam::NoDefaultAlpn => SVCB_KEY_NO_DEFAULT_ALPN,
            SvcParam::Port(_) => SVCB_KEY_PORT,
            SvcParam::Ipv4Hint(_) => SVCB_KEY_IPV4HINT,
            SvcParam::Ech(_) => SVCB_KEY_ECHCONFIG,
            SvcParam::Ipv6Hint(_) => SVCB_KEY_IPV6HINT,
            SvcParam::DoHPath(_) => SVCB_KEY_DOHPATH,
        }
    }
}

/// One record ready to cross the boundary: owner name, TTL and body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedRecord {
    /// `dns.Fqdn(name)`: the name the record is attached to.
    pub owner: String,
    /// TTL the caller asked for (the rule's, or the config default).
    pub ttl: u32,
    /// The record body.
    pub record: Record,
}

/// Builds the record `type_name`/`value` describes for a `qtype` query on `name`.
///
/// `Ok(None)` is the "type does not answer this query" answer the Go caller turned into a `nil`
/// record, which is what makes a matched rule a `NODATA` reply instead of leaking the name
/// upstream. `Err` carries the message the old Go function returned.
pub fn build(
    name: &str,
    qtype: u16,
    type_name: &str,
    value: &str,
    ttl: u32,
) -> Result<Option<ParsedRecord>, String> {
    let rrtype =
        lookup_type(type_name).ok_or_else(|| format!("不支持的记录类型 {:?}", type_name))?;

    // CNAME is a property of the name itself, not of the query type.
    if rrtype != TYPE_CNAME && rrtype != qtype {
        return Ok(None);
    }

    let trimmed = go_trim_space(value);
    let record = match rrtype {
        TYPE_A => Record::A(
            ipv4_literal(trimmed)
                .ok_or_else(|| format!("A 记录的取值 {:?} 不是合法的 IPv4 地址", value))?,
        ),
        TYPE_AAAA => Record::Aaaa(
            ipv6_literal(trimmed)
                .ok_or_else(|| format!("AAAA 记录的取值 {:?} 不是合法的 IPv6 地址", value))?,
        ),
        TYPE_CNAME => Record::Cname(target_name(value, "CNAME")?),
        TYPE_NS => Record::Ns(target_name(value, "NS")?),
        TYPE_PTR => Record::Ptr(target_name(value, "PTR")?),
        TYPE_TXT => {
            if trimmed.is_empty() {
                return Err("TXT 记录缺少取值".to_string());
            }
            Record::Txt(vec![trimmed.to_string()])
        }
        TYPE_MX => build_mx(value)?,
        TYPE_SRV => build_srv(value)?,
        TYPE_HTTPS | TYPE_SVCB => build_svcb(value, rrtype == TYPE_HTTPS)?,
        other => return Err(format!("记录类型 {} 暂未实现", other)),
    };

    Ok(Some(ParsedRecord {
        owner: fqdn(name),
        ttl,
        record,
    }))
}

/// The supported record type names, sorted, for the UI dropdown and the `$dnsrewrite` check.
pub fn type_names() -> &'static [&'static str] {
    &SORTED_TYPE_NAMES
}

/// The numeric type a configured type name resolves to, or `None` when the kernel does not
/// support it (the same answer [`build`] gives, exposed for the rewrite engine's compile pass).
pub fn type_number(type_name: &str) -> Option<u16> {
    lookup_type(type_name)
}

/// Resolves a configured type name (`strings.ToUpper(strings.TrimSpace(...))`).
fn lookup_type(type_name: &str) -> Option<u16> {
    let upper = go_upper(go_trim_space(type_name));
    RECORD_TYPES
        .iter()
        .find(|(name, _)| *name == upper.as_ref())
        .map(|(_, code)| *code)
}

/// A target host for CNAME/NS/PTR, fully qualified.
fn target_name(value: &str, type_name: &str) -> Result<String, String> {
    if !is_rewrite_target(value) {
        return Err(format!("{type_name} 记录的取值 {:?} 不是合法的域名", value));
    }
    Ok(fqdn(go_trim_space(value)))
}

/// `MX "32 example.mail"`.
fn build_mx(value: &str) -> Result<Record, String> {
    let fields: Vec<&str> = value.split_whitespace().collect();
    if fields.len() != 2 {
        return Err(format!(
            "MX 记录需要「优先级 交换主机」两个字段，得到 {:?}",
            value
        ));
    }
    let preference = parse_u16(fields[0]).map_err(|error| format!("MX 优先级无效: {error}"))?;
    if !is_rewrite_target(fields[1]) {
        return Err(format!("MX 交换主机 {:?} 不是合法的域名", fields[1]));
    }
    Ok(Record::Mx {
        preference,
        exchange: fqdn(fields[1]),
    })
}

/// `SRV "10 60 8080 example.com"`.
fn build_srv(value: &str) -> Result<Record, String> {
    let fields: Vec<&str> = value.split_whitespace().collect();
    if fields.len() != 4 {
        return Err(format!(
            "SRV 记录需要「优先级 权重 端口 目标」四个字段，得到 {:?}",
            value
        ));
    }
    let priority = parse_u16(fields[0]).map_err(|error| format!("SRV 优先级无效: {error}"))?;
    let weight = parse_u16(fields[1]).map_err(|error| format!("SRV 权重无效: {error}"))?;
    let port = parse_u16(fields[2]).map_err(|error| format!("SRV 端口无效: {error}"))?;
    if !is_rewrite_target(fields[3]) {
        return Err(format!("SRV 目标 {:?} 不是合法的域名", fields[3]));
    }
    Ok(Record::Srv {
        priority,
        weight,
        port,
        target: fqdn(fields[3]),
    })
}

/// `HTTPS "1 . alpn=h3,h2 port=8443"` / `SVCB "1 svc.example. alpn=h3"`.
fn build_svcb(value: &str, https: bool) -> Result<Record, String> {
    let fields: Vec<&str> = value.split_whitespace().collect();
    if fields.len() < 2 {
        return Err(format!(
            "SVCB/HTTPS 记录至少需要「优先级 目标」两个字段，得到 {:?}",
            value
        ));
    }
    let priority = parse_u16(fields[0]).map_err(|error| format!("SVCB 优先级无效: {error}"))?;

    // `.` means "the query name itself", the most common SVCB target.
    let target = if fields[1] == "." {
        ".".to_string()
    } else {
        if !is_rewrite_target(fields[1]) {
            return Err(format!("SVCB 目标 {:?} 不是合法的域名", fields[1]));
        }
        fqdn(fields[1])
    };

    Ok(Record::Svcb {
        https,
        priority,
        target,
        params: parse_svcb_params(&fields[2..])?,
    })
}

/// Parses `key=value` / bare `key` parameters, rejecting duplicates.
fn parse_svcb_params(params: &[&str]) -> Result<Vec<SvcParam>, String> {
    let mut out = Vec::with_capacity(params.len());
    let mut seen: Vec<u16> = Vec::with_capacity(params.len());
    for raw in params {
        let (key, value, has_value) = match raw.split_once('=') {
            Some((key, value)) => (key, value.trim_matches('"'), true),
            None => (*raw, "", false),
        };
        let param = build_svcb_param(&go_lower(key), value, has_value)?;
        if seen.contains(&param.key()) {
            return Err(format!("SVCB 参数 {key} 重复出现"));
        }
        seen.push(param.key());
        out.push(param);
    }
    Ok(out)
}

/// Builds one parameter; `key` is already lowercased, like the Go version.
fn build_svcb_param(key: &str, value: &str, has_value: bool) -> Result<SvcParam, String> {
    match key {
        "alpn" => Ok(SvcParam::Alpn(split_list(value, has_value, "alpn")?)),
        "port" => Ok(SvcParam::Port(
            parse_u16(value).map_err(|error| format!("port 参数无效: {error}"))?,
        )),
        "ipv4hint" => Ok(SvcParam::Ipv4Hint(vec![ipv4_literal(value).ok_or_else(
            || format!("ipv4hint 参数 {:?} 不是合法的 IPv4 地址", value),
        )?])),
        "ipv6hint" => Ok(SvcParam::Ipv6Hint(vec![ipv6_hint(value).ok_or_else(
            || format!("ipv6hint 参数 {:?} 不是合法的 IPv6 地址", value),
        )?])),
        "dohpath" => {
            if value.is_empty() {
                return Err("dohpath 参数缺少取值".to_string());
            }
            Ok(SvcParam::DoHPath(value.to_string()))
        }
        "ech" => {
            let raw = BASE64
                .decode(value)
                .map_err(|error| format!("ech 参数不是合法的 Base64 文本: {error}"))?;
            Ok(SvcParam::Ech(raw))
        }
        "no-default-alpn" => Ok(SvcParam::NoDefaultAlpn),
        "mandatory" => {
            let names = split_list(value, has_value, "mandatory")?;
            let mut codes = Vec::with_capacity(names.len());
            for name in names {
                let lowered = go_lower(&name);
                let code = SVCB_KEY_NAMES
                    .iter()
                    .find(|(candidate, _)| *candidate == lowered.as_ref())
                    .map(|(_, code)| *code)
                    .ok_or_else(|| format!("mandatory 参数引用了未知的键 {:?}", name))?;
                codes.push(code);
            }
            Ok(SvcParam::Mandatory(codes))
        }
        other => Err(format!("不支持的 SVCB 参数 {:?}", other)),
    }
}

/// A comma separated list; `alpn` and `mandatory` take one, the hints do not.
fn split_list(value: &str, has_value: bool, key: &str) -> Result<Vec<String>, String> {
    if !has_value || go_trim_space(value).is_empty() {
        return Err(format!("{key} 参数缺少取值"));
    }
    let mut out = Vec::new();
    for part in value.split(',') {
        let part = go_trim_space(part);
        if part.is_empty() {
            return Err(format!("{key} 参数含空取值"));
        }
        out.push(part.to_string());
    }
    Ok(out)
}

/// `strconv.ParseUint(..., 10, 16)`; Go rejects a sign prefix, so `+1` is not a port.
fn parse_u16(value: &str) -> Result<u16, String> {
    let trimmed = go_trim_space(value);
    let invalid = || format!("{:?} 不是 0-65535 之间的整数", value);
    if trimmed.starts_with('+') || trimmed.starts_with('-') {
        return Err(invalid());
    }
    trimmed.parse::<u16>().map_err(|_| invalid())
}

/// `net.ParseIP` + `To4`: a plain IPv4 literal or an IPv4-mapped IPv6 literal.
fn ipv4_literal(value: &str) -> Option<[u8; 4]> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(address.octets());
    }
    let address = value.parse::<Ipv6Addr>().ok()?;
    mapped_ipv4(address.octets())
}

/// Go's `To4` only converts the `::ffff:a.b.c.d` form, not `::a.b.c.d`.
pub(crate) fn mapped_ipv4(octets: [u8; 16]) -> Option<[u8; 4]> {
    let mapped =
        octets[..10].iter().all(|byte| *byte == 0) && octets[10] == 0xff && octets[11] == 0xff;
    if mapped {
        Some([octets[12], octets[13], octets[14], octets[15]])
    } else {
        None
    }
}

/// A real IPv6 address: an IPv4 literal (and its v4-mapped form) is refused, as Go's `To4` check did.
fn ipv6_literal(value: &str) -> Option<[u8; 16]> {
    if value.parse::<Ipv4Addr>().is_ok() {
        return None;
    }
    let octets = value.parse::<Ipv6Addr>().ok()?.octets();
    if mapped_ipv4(octets).is_some() {
        return None;
    }
    Some(octets)
}

/// `To16`: unlike [`ipv6_literal`], the hints accept an IPv4 literal and map it.
fn ipv6_hint(value: &str) -> Option<[u8; 16]> {
    if let Ok(address) = value.parse::<Ipv4Addr>() {
        return Some(address.to_ipv6_mapped().octets());
    }
    value
        .parse::<Ipv6Addr>()
        .ok()
        .map(|address| address.octets())
}

/// `dns.Fqdn`: one trailing dot, `.` for the empty name.
pub(crate) fn fqdn(name: &str) -> String {
    if name.is_empty() {
        return ".".to_string();
    }
    if is_fqdn(name) {
        return name.to_string();
    }
    format!("{name}.")
}

/// `dns.IsFqdn`: a trailing dot that is not escaped by an odd number of backslashes.
fn is_fqdn(name: &str) -> bool {
    let Some(rest) = name.strip_suffix('.') else {
        return false;
    };
    let backslashes = rest.chars().rev().take_while(|c| *c == '\\').count();
    backslashes % 2 == 0
}

/// `isRewriteTarget`: a usable rewrite target name.
///
/// Deliberately no "must contain a dot" rule: rewrite targets are often single-label intranet
/// hostnames (`nas`), which has nothing to do with the dot a filter pattern needs.
fn is_rewrite_target(target: &str) -> bool {
    let trimmed = go_trim_space(target);
    let candidate = trimmed.strip_suffix('.').unwrap_or(trimmed);
    if candidate.is_empty() || candidate.len() > 253 {
        return false;
    }
    if candidate.parse::<Ipv4Addr>().is_ok() || candidate.parse::<Ipv6Addr>().is_ok() {
        return false;
    }
    for label in candidate.split('.') {
        if label.is_empty() || label.len() > 63 {
            return false;
        }
    }
    uts46()
        .to_ascii(
            candidate.as_bytes(),
            AsciiDenyList::STD3,
            Hyphens::Check,
            DnsLength::Ignore,
        )
        .map(|ascii| !ascii.is_empty())
        .unwrap_or(false)
}

/// `idna.Lookup`: UTS 46, non-transitional, STD3 rules, hyphens checked, no DNS length check
/// (the 253-byte limit is applied by the caller, like the Go version did).
fn uts46() -> &'static Uts46 {
    static LOOKUP: OnceLock<Uts46> = OnceLock::new();
    LOOKUP.get_or_init(Uts46::new)
}

#[cfg(test)]
mod tests;

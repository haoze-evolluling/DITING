use std::net::{Ipv4Addr, Ipv6Addr};

use crate::build::name::NameWriter;
use crate::build::types::{
    SVCB_KEY_ALPN, SVCB_KEY_DOHPATH, SVCB_KEY_IPV4HINT, SVCB_KEY_IPV6HINT,
    SVCB_KEY_NO_DEFAULT_ALPN, SVCB_KEY_PORT, TYPE_A, TYPE_AAAA, TYPE_CAA, TYPE_CNAME, TYPE_HINFO,
    TYPE_HTTPS, TYPE_MX, TYPE_NAPTR, TYPE_NS, TYPE_PTR, TYPE_SOA, TYPE_SRV, TYPE_SVCB, TYPE_TXT,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RData {
    A(Ipv4Addr),
    Aaaa(Ipv6Addr),
    Cname(String),
    Ptr(String),
    Ns(String),
    Soa {
        mname: String,
        rname: String,
        serial: u32,
        refresh: u32,
        retry: u32,
        expire: u32,
        minimum: u32,
    },
    Mx {
        preference: u16,
        exchange: String,
    },
    Txt(Vec<Vec<u8>>),
    Srv {
        priority: u16,
        weight: u16,
        port: u16,
        target: String,
    },
    Https(SvcbRData),
    Svcb(SvcbRData),
    Hinfo {
        cpu: String,
        os: String,
    },
    Caa {
        flags: u8,
        tag: String,
        value: Vec<u8>,
    },
    Naptr {
        order: u16,
        preference: u16,
        flags: String,
        services: String,
        regexp: String,
        replacement: String,
    },
    Raw(Vec<u8>),
}

impl RData {
    pub fn txt<T: AsRef<[u8]>>(values: impl IntoIterator<Item = T>) -> Self {
        RData::Txt(
            values
                .into_iter()
                .map(|value| value.as_ref().to_vec())
                .collect(),
        )
    }

    pub fn rtype(&self) -> Option<u16> {
        Some(match self {
            RData::A(_) => TYPE_A,
            RData::Aaaa(_) => TYPE_AAAA,
            RData::Cname(_) => TYPE_CNAME,
            RData::Ptr(_) => TYPE_PTR,
            RData::Ns(_) => TYPE_NS,
            RData::Soa { .. } => TYPE_SOA,
            RData::Mx { .. } => TYPE_MX,
            RData::Txt(_) => TYPE_TXT,
            RData::Srv { .. } => TYPE_SRV,
            RData::Https(_) => TYPE_HTTPS,
            RData::Svcb(_) => TYPE_SVCB,
            RData::Hinfo { .. } => TYPE_HINFO,
            RData::Caa { .. } => TYPE_CAA,
            RData::Naptr { .. } => TYPE_NAPTR,
            RData::Raw(_) => return None,
        })
    }

    pub fn encode(&self, names: &mut NameWriter, out: &mut Vec<u8>) -> bool {
        match self {
            RData::A(address) => out.extend_from_slice(&address.octets()),
            RData::Aaaa(address) => out.extend_from_slice(&address.octets()),
            RData::Cname(target) | RData::Ptr(target) | RData::Ns(target) => {
                if !names.write_name(out, target) {
                    return false;
                }
            }
            RData::Soa {
                mname,
                rname,
                serial,
                refresh,
                retry,
                expire,
                minimum,
            } => {
                if !names.write_name(out, mname) || !names.write_name(out, rname) {
                    return false;
                }
                for value in [*serial, *refresh, *retry, *expire, *minimum] {
                    out.extend_from_slice(&value.to_be_bytes());
                }
            }
            RData::Mx {
                preference,
                exchange,
            } => {
                out.extend_from_slice(&preference.to_be_bytes());
                if !names.write_name(out, exchange) {
                    return false;
                }
            }
            RData::Txt(strings) => {
                for string in strings {
                    if !write_character_string(out, string) {
                        return false;
                    }
                }
            }
            RData::Srv {
                priority,
                weight,
                port,
                target,
            } => {
                out.extend_from_slice(&priority.to_be_bytes());
                out.extend_from_slice(&weight.to_be_bytes());
                out.extend_from_slice(&port.to_be_bytes());
                if !names.write_name(out, target) {
                    return false;
                }
            }
            RData::Svcb(data) | RData::Https(data) => {
                if !write_svcb(data, out) {
                    return false;
                }
            }
            RData::Hinfo { cpu, os } => {
                if !write_character_string(out, cpu.as_bytes())
                    || !write_character_string(out, os.as_bytes())
                {
                    return false;
                }
            }
            RData::Caa { flags, tag, value } => {
                out.push(*flags);
                if !write_character_string(out, tag.as_bytes()) {
                    return false;
                }
                out.extend_from_slice(value);
            }
            RData::Naptr {
                order,
                preference,
                flags,
                services,
                regexp,
                replacement,
            } => {
                out.extend_from_slice(&order.to_be_bytes());
                out.extend_from_slice(&preference.to_be_bytes());
                for value in [flags, services, regexp] {
                    if !write_character_string(out, value.as_bytes()) {
                        return false;
                    }
                }
                if !crate::pack_name(replacement, out) {
                    return false;
                }
            }
            RData::Raw(data) => out.extend_from_slice(data),
        }
        true
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SvcbRData {
    pub priority: u16,
    pub target: String,
    pub params: Vec<SvcParam>,
}

impl SvcbRData {
    pub fn new(priority: u16, target: impl Into<String>) -> Self {
        Self {
            priority,
            target: target.into(),
            params: Vec::new(),
        }
    }

    pub fn push(mut self, param: SvcParam) -> Self {
        self.params.push(param);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SvcParam {
    pub key: u16,
    pub value: Vec<u8>,
}

impl SvcParam {
    pub fn new(key: u16, value: Vec<u8>) -> Self {
        Self { key, value }
    }

    pub fn alpn(protocols: &[&str]) -> Self {
        let mut value = Vec::new();
        for protocol in protocols {
            debug_assert!(
                !protocol.is_empty() && protocol.len() <= u8::MAX as usize,
                "alpn protocol identifiers must be 1..=255 bytes"
            );
            value.push(protocol.len() as u8);
            value.extend_from_slice(protocol.as_bytes());
        }
        Self::new(SVCB_KEY_ALPN, value)
    }

    pub fn no_default_alpn() -> Self {
        Self::new(SVCB_KEY_NO_DEFAULT_ALPN, Vec::new())
    }

    pub fn port(port: u16) -> Self {
        Self::new(SVCB_KEY_PORT, port.to_be_bytes().to_vec())
    }

    pub fn ipv4hint(addresses: &[Ipv4Addr]) -> Self {
        let mut value = Vec::with_capacity(addresses.len() * 4);
        for address in addresses {
            value.extend_from_slice(&address.octets());
        }
        Self::new(SVCB_KEY_IPV4HINT, value)
    }

    pub fn ipv6hint(addresses: &[Ipv6Addr]) -> Self {
        let mut value = Vec::with_capacity(addresses.len() * 16);
        for address in addresses {
            value.extend_from_slice(&address.octets());
        }
        Self::new(SVCB_KEY_IPV6HINT, value)
    }

    pub fn dohpath(path: &str) -> Self {
        Self::new(SVCB_KEY_DOHPATH, path.as_bytes().to_vec())
    }
}

fn write_svcb(data: &SvcbRData, out: &mut Vec<u8>) -> bool {
    out.extend_from_slice(&data.priority.to_be_bytes());
    if !crate::pack_name(&data.target, out) {
        return false;
    }

    let mut params: Vec<&SvcParam> = data.params.iter().collect();
    params.sort_by_key(|param| param.key);
    for pair in params.windows(2) {
        if pair[0].key == pair[1].key {
            return false;
        }
    }
    for param in params {
        if param.value.len() > u16::MAX as usize {
            return false;
        }
        out.extend_from_slice(&param.key.to_be_bytes());
        out.extend_from_slice(&(param.value.len() as u16).to_be_bytes());
        out.extend_from_slice(&param.value);
    }
    true
}

fn write_character_string(out: &mut Vec<u8>, value: &[u8]) -> bool {
    if value.len() > u8::MAX as usize {
        return false;
    }
    out.push(value.len() as u8);
    out.extend_from_slice(value);
    true
}

use std::net::{Ipv4Addr, Ipv6Addr};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Addr {
    V4([u8; 4]),
    V6([u8; 16]),
}

impl Addr {
    pub fn width(&self) -> usize {
        match self {
            Addr::V4(_) => 4,
            Addr::V6(_) => 16,
        }
    }

    pub fn as_bytes(&self) -> &[u8] {
        match self {
            Addr::V4(bytes) => bytes,
            Addr::V6(bytes) => bytes,
        }
    }

    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        match bytes.len() {
            4 => {
                let mut out = [0u8; 4];
                out.copy_from_slice(bytes);
                Some(Addr::V4(out))
            }
            16 => {
                let mut out = [0u8; 16];
                out.copy_from_slice(bytes);
                Some(Addr::V6(out))
            }
            _ => None,
        }
    }
}

pub fn parse_ip(text: &str) -> Option<Addr> {
    if let Ok(v4) = text.parse::<Ipv4Addr>() {
        return Some(Addr::V4(v4.octets()));
    }
    let v6 = text.parse::<Ipv6Addr>().ok()?;
    if let Some(v4) = v4_of_mapped(&v6) {
        return Some(Addr::V4(v4));
    }
    Some(Addr::V6(v6.octets()))
}

pub fn parse_hosts_address(raw: &str) -> Option<Addr> {
    let raw = match raw.find('%') {
        Some(index) => &raw[..index],
        None => raw,
    };
    parse_ip(raw)
}

pub fn collapse_v6(bytes: [u8; 16]) -> Addr {
    match v4_of_mapped(&Ipv6Addr::from(bytes)) {
        Some(v4) => Addr::V4(v4),
        None => Addr::V6(bytes),
    }
}

fn v4_of_mapped(v6: &Ipv6Addr) -> Option<[u8; 4]> {
    v6.to_ipv4_mapped().map(|v4| v4.octets())
}

#[cfg(test)]
mod tests;

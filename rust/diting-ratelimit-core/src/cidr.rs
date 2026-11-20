use std::net::{Ipv4Addr, Ipv6Addr};

use crate::ip::Addr;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Cidr {
    network: Addr,
    prefix: u8,
}

impl Cidr {
    pub fn parse(text: &str) -> Option<Self> {
        let slash = text.find('/')?;
        let (address, mask) = (&text[..slash], &text[slash + 1..]);

        let (raw, width) = if let Ok(address) = address.parse::<Ipv4Addr>() {
            (Addr::V4(address.octets()), 32u32)
        } else {
            let address = address.parse::<Ipv6Addr>().ok()?;
            (Addr::V6(address.octets()), 128u32)
        };

        if mask.is_empty() || !mask.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        let prefix: u32 = mask.parse().ok()?;
        if prefix > width {
            return None;
        }

        let masked = raw.masked(prefix as u8);
        Some(match masked {
            Addr::V6(bytes) if is_v4_mapped(&bytes) => Cidr {
                network: Addr::V4([bytes[12], bytes[13], bytes[14], bytes[15]]),
                prefix: (prefix - 96) as u8,
            },
            other => Cidr {
                network: other,
                prefix: prefix as u8,
            },
        })
    }

    pub fn contains(&self, address: &Addr) -> bool {
        if address.width() != self.network.width() {
            return false;
        }
        address.masked(self.prefix) == self.network
    }
}

fn is_v4_mapped(raw: &[u8; 16]) -> bool {
    raw[..10].iter().all(|byte| *byte == 0) && raw[10] == 0xff && raw[11] == 0xff
}

#[cfg(test)]
mod tests;

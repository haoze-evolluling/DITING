use std::net::{Ipv4Addr, Ipv6Addr};

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Addr {
    V4([u8; 4]),
    V6([u8; 16]),
}

impl Addr {
    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        match bytes.len() {
            4 => Some(Addr::V4(bytes.try_into().ok()?)),
            16 => {
                let raw: [u8; 16] = bytes.try_into().ok()?;
                Some(Self::from_v6(raw))
            }
            _ => None,
        }
    }

    pub fn parse(text: &str) -> Option<Self> {
        if text.contains(':') {
            text.parse::<Ipv6Addr>()
                .ok()
                .map(|address| Self::from_v6(address.octets()))
        } else {
            text.parse::<Ipv4Addr>()
                .ok()
                .map(|address| Addr::V4(address.octets()))
        }
    }

    fn from_v6(raw: [u8; 16]) -> Self {
        if raw[..10].iter().all(|byte| *byte == 0) && raw[10] == 0xff && raw[11] == 0xff {
            return Addr::V4([raw[12], raw[13], raw[14], raw[15]]);
        }
        Addr::V6(raw)
    }

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

    pub fn masked(&self, prefix: u8) -> Addr {
        let width_bits = self.width() * 8;
        debug_assert!(usize::from(prefix) <= width_bits);
        match *self {
            Addr::V4(bytes) => Addr::V4(mask_bytes(bytes, prefix)),
            Addr::V6(bytes) => Addr::V6(mask_bytes(bytes, prefix)),
        }
    }
}

fn mask_bytes<const N: usize>(mut bytes: [u8; N], prefix: u8) -> [u8; N] {
    for (index, byte) in bytes.iter_mut().enumerate() {
        let remaining = i32::from(prefix) - (index as i32) * 8;
        let mask = if remaining >= 8 {
            0xff
        } else if remaining <= 0 {
            0x00
        } else {
            (0xffu16 << (8 - remaining as u16)) as u8
        };
        *byte &= mask;
    }
    bytes
}

#[cfg(test)]
mod tests;

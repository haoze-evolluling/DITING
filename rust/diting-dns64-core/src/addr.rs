#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Family {
    V4,
    V6,
}

impl Family {
    pub fn bits(self) -> u32 {
        match self {
            Family::V4 => 32,
            Family::V6 => 128,
        }
    }
}

const V4_IN_V6_PREFIX: [u8; 12] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff];

pub fn parse_addr(text: &str) -> Option<(Family, [u8; 16])> {
    if let Ok(v4) = text.parse::<std::net::Ipv4Addr>() {
        return Some((Family::V4, v4.to_ipv6_mapped().octets()));
    }
    if let Ok(v6) = text.parse::<std::net::Ipv6Addr>() {
        return Some((Family::V6, v6.octets()));
    }
    None
}

pub fn to4(bytes: &[u8]) -> Option<[u8; 4]> {
    match bytes.len() {
        4 => Some([bytes[0], bytes[1], bytes[2], bytes[3]]),
        16 => {
            if bytes[..12] == V4_IN_V6_PREFIX {
                Some([bytes[12], bytes[13], bytes[14], bytes[15]])
            } else {
                None
            }
        }
        _ => None,
    }
}

pub fn map_v4(bytes: [u8; 4]) -> [u8; 16] {
    let mut out = [0u8; 16];
    out[..12].copy_from_slice(&V4_IN_V6_PREFIX);
    out[12..].copy_from_slice(&bytes);
    out
}

pub fn mask16(ones: u8) -> [u8; 16] {
    let mut mask = [0u8; 16];
    let full = usize::from(ones / 8);
    for byte in mask.iter_mut().take(full.min(16)) {
        *byte = 0xff;
    }
    let rest = usize::from(ones % 8);
    if full < 16 && rest > 0 {
        mask[full] = 0xff << (8 - rest);
    }
    mask
}

pub fn mask4(ones: u8) -> [u8; 4] {
    let mut mask = [0u8; 4];
    let full = usize::from(ones / 8);
    for byte in mask.iter_mut().take(full.min(4)) {
        *byte = 0xff;
    }
    let rest = usize::from(ones % 8);
    if full < 4 && rest > 0 {
        mask[full] = 0xff << (8 - rest);
    }
    mask
}

pub fn apply_mask16(bytes: &[u8; 16], mask: &[u8; 16]) -> [u8; 16] {
    let mut out = [0u8; 16];
    for (index, byte) in out.iter_mut().enumerate() {
        *byte = bytes[index] & mask[index];
    }
    out
}

pub fn apply_mask4(bytes: &[u8; 4], mask: &[u8; 4]) -> [u8; 4] {
    let mut out = [0u8; 4];
    for (index, byte) in out.iter_mut().enumerate() {
        *byte = bytes[index] & mask[index];
    }
    out
}

pub fn parse_digits(text: &str) -> Option<u32> {
    if text.is_empty() {
        return None;
    }
    let mut value: u32 = 0;
    for byte in text.bytes() {
        if !byte.is_ascii_digit() {
            return None;
        }
        value = value.checked_mul(10)?.checked_add(u32::from(byte - b'0'))?;
    }
    Some(value)
}

#[cfg(test)]
mod tests;

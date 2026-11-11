//! The address arithmetic behind the DNS64 kernel: `netip.ParseAddr` text rules, Go's `To4`
//! folding, and CIDR mask application.
//!
//! The kernel only ever sees IPv6 the way the old Go code did: as 16 bytes coming out of
//! `net.ParseIP` (so a dotted-quad text is the IPv4-mapped form), plus 4-byte addresses when Go
//! hands over `IP.To4()` output.

/// Address families as `netip.ParseAddr` reports them: the mask length bound depends on this,
/// not on the bytes.
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

/// IPv4-mapped prefix `::ffff:0:0` — the first 12 bytes of any 16-byte IPv4 address.
const V4_IN_V6_PREFIX: [u8; 12] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff];

/// Parses the address part of a CIDR the way `netip.ParseAddr` does, returning the family and the
/// `As16` bytes.
///
/// Zones are rejected here (`fe80::1%eth0`): `ParseCIDR` rejects them too, so the kernel never has
/// to carry one.
pub fn parse_addr(text: &str) -> Option<(Family, [u8; 16])> {
    if let Ok(v4) = text.parse::<std::net::Ipv4Addr>() {
        return Some((Family::V4, v4.to_ipv6_mapped().octets()));
    }
    if let Ok(v6) = text.parse::<std::net::Ipv6Addr>() {
        return Some((Family::V6, v6.octets()));
    }
    None
}

/// Go's `IP.To4`: 4-byte addresses pass through, 16-byte IPv4-mapped ones collapse, everything
/// else (including `::`) is not an IPv4 address.
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

/// Go's `IPv4(a, b, c, d)`: the mapped 16-byte form used by `IP.To16`.
pub fn map_v4(bytes: [u8; 4]) -> [u8; 16] {
    let mut out = [0u8; 16];
    out[..12].copy_from_slice(&V4_IN_V6_PREFIX);
    out[12..].copy_from_slice(&bytes);
    out
}

/// The 16-byte mask for `ones` bits, the way `net.CIDRMask(ones, 128)` builds it.
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

/// The 4-byte mask for `ones` bits (`net.CIDRMask(ones, 32)`).
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

/// Applies a 16-byte mask.
pub fn apply_mask16(bytes: &[u8; 16], mask: &[u8; 16]) -> [u8; 16] {
    let mut out = [0u8; 16];
    for (index, byte) in out.iter_mut().enumerate() {
        *byte = bytes[index] & mask[index];
    }
    out
}

/// Applies a 4-byte mask.
pub fn apply_mask4(bytes: &[u8; 4], mask: &[u8; 4]) -> [u8; 4] {
    let mut out = [0u8; 4];
    for (index, byte) in out.iter_mut().enumerate() {
        *byte = bytes[index] & mask[index];
    }
    out
}

/// Go's `dtoi`: digits only, the whole string must be consumed, no sign and no leading-zero
/// restriction.
///
/// `None` means the mask is malformed, which `ParseCIDR` turns into a parse error; values above
/// the family's bit length are a parse error there as well, so overflow is not distinguished.
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

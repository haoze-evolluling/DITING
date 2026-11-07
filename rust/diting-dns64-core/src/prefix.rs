//! CIDR parsing with `net.ParseCIDR`'s exact outcomes, plus the two shapes the old DNS64 code
//! relied on: the RFC 6052 prefix list and the RFC 6147 exclusion set.
//!
//! `net.ParseCIDR` keeps `*net.IPNet` in the width its mask implies, and `IPNet.Contains` folds
//! both sides through `To4` before comparing widths. That fold is why `::ffff:0:0/96` — one of the
//! default exclusions — ends up matching **every** IPv4 address: the network collapses to
//! `0.0.0.0` with a zero mask. The corpus pins that behaviour, so this module reproduces it
//! instead of "fixing" it: the old service relied on mapped answers being excluded, and a
//! narrower rule would start synthesising AAAA records for addresses it used to skip.

use crate::addr::{
    apply_mask16, apply_mask4, mask16, mask4, parse_addr, parse_digits, to4, Family,
};

/// RFC 6052 section 2.2: the prefix lengths an IPv6 address may be embedded behind.
pub const DNS64_PREFIX_LENGTHS: [u8; 6] = [32, 40, 48, 56, 64, 96];

/// Why a configured prefix was rejected. The message text lives in Go, where the old errors were
/// written; the kernel only says which of the two it was.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PrefixError {
    /// `net.ParseCIDR` would have returned an error.
    Parse,
    /// Parsed, but not an IPv6 prefix of an RFC 6052 length (this includes every IPv4 CIDR).
    Length,
}

/// A network the way `*net.IPNet` + `networkNumberAndMask` see it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Net {
    /// A network whose address is an IPv4 address — either from `/24`-style text or from an
    /// IPv4-mapped IPv6 address, which `networkNumberAndMask` collapses the same way.
    V4 { number: [u8; 4], mask: [u8; 4] },
    /// A real IPv6 network.
    V6 { number: [u8; 16], mask: [u8; 16] },
}

impl Net {
    /// `(*net.IPNet).Contains`, including the `To4` fold on both sides.
    pub fn contains(&self, bytes: &[u8]) -> bool {
        match (self, to4(bytes)) {
            (Net::V4 { number, mask }, Some(ip)) => number
                .iter()
                .zip(mask)
                .zip(&ip)
                .all(|((n, m), i)| n & m == i & m),
            (Net::V6 { number, mask }, None) if bytes.len() == 16 => number
                .iter()
                .zip(mask)
                .zip(bytes)
                .all(|((n, m), i)| n & m == i & m),
            _ => false,
        }
    }
}

/// What `net.ParseCIDR` returns, restricted to what this kernel needs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cidr {
    /// The network in `IPNet` form.
    pub net: Net,
    /// `IPNet.IP.To16()`: the starting bytes RFC 6052 embedding copies from.
    pub addr16: [u8; 16],
    /// The prefix length.
    pub ones: u8,
    /// The family's bit length (`IPNet.Mask.Size()`).
    pub bits: u32,
}

/// Parses `text` the way `net.ParseCIDR` does.
pub fn parse_cidr(text: &str) -> Result<Cidr, PrefixError> {
    let Some((addr, mask)) = text.split_once('/') else {
        return Err(PrefixError::Parse);
    };
    let Some((family, addr16)) = parse_addr(addr) else {
        return Err(PrefixError::Parse);
    };
    let Some(ones) = parse_digits(mask) else {
        return Err(PrefixError::Parse);
    };
    if ones > family.bits() {
        return Err(PrefixError::Parse);
    }
    let ones = ones as u8;

    match family {
        Family::V4 => {
            let mask = mask4(ones);
            let mut low = [0u8; 4];
            low.copy_from_slice(&addr16[12..]);
            let number = apply_mask4(&low, &mask);
            Ok(Cidr {
                net: Net::V4 { number, mask },
                addr16: crate::addr::map_v4(number),
                ones,
                bits: 32,
            })
        }
        Family::V6 => {
            let mask = mask16(ones);
            let number = apply_mask16(&addr16, &mask);
            // `IPNet.IP` is the masked address; an IPv4-mapped one collapses again inside
            // `networkNumberAndMask` and inside `To16`.
            match to4(&number) {
                Some(mapped) => Ok(Cidr {
                    net: Net::V4 {
                        number: mapped,
                        mask: [mask[12], mask[13], mask[14], mask[15]],
                    },
                    addr16: crate::addr::map_v4(mapped),
                    ones,
                    bits: 128,
                }),
                None => Ok(Cidr {
                    net: Net::V6 { number, mask },
                    addr16: number,
                    ones,
                    bits: 128,
                }),
            }
        }
    }
}

/// An RFC 6052 prefix: the masked address and its length.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Prefix {
    pub addr: [u8; 16],
    pub ones: u8,
}

impl Prefix {
    /// `EmbedIPv4InIPv6`: places a 4-byte address behind this prefix.
    pub fn embed(&self, v4: [u8; 4]) -> [u8; 16] {
        let mut v6 = self.addr;
        match self.ones {
            96 => v6[12..16].copy_from_slice(&v4),
            64 => {
                v6[9..13].copy_from_slice(&v4);
                v6[8] = 0;
            }
            56 => {
                v6[7] = v4[0];
                v6[9..12].copy_from_slice(&v4[1..4]);
                v6[8] = 0;
            }
            48 => {
                v6[6..8].copy_from_slice(&v4[0..2]);
                v6[9..11].copy_from_slice(&v4[2..4]);
                v6[8] = 0;
            }
            40 => {
                v6[5..8].copy_from_slice(&v4[0..3]);
                v6[9] = v4[3];
                v6[8] = 0;
            }
            32 => {
                v6[4..8].copy_from_slice(&v4);
                v6[8] = 0;
            }
            // Unreachable: `parse_dns64_prefix` only accepts the lengths above.
            _ => {}
        }
        v6
    }
}

/// The well-known prefix from RFC 6052, used when no prefix is configured.
pub fn well_known_prefix() -> Prefix {
    parse_dns64_prefix("64:ff9b::/96")
        .expect("the well-known prefix parses")
        .0
}

/// Parses a configured prefix and enforces the RFC 6052 length set.
///
/// The network comes back with it because the old constructor adds exactly that `*net.IPNet` to
/// the exclusion set — including the `To4` collapse `::/96` and friends pick up there.
pub fn parse_dns64_prefix(text: &str) -> Result<(Prefix, Net), PrefixError> {
    let cidr = parse_cidr(text)?;
    if cidr.bits != 128 || !DNS64_PREFIX_LENGTHS.contains(&cidr.ones) {
        return Err(PrefixError::Length);
    }
    Ok((
        Prefix {
            addr: cidr.addr16,
            ones: cidr.ones,
        },
        cidr.net,
    ))
}

/// `net.IP.IsUnspecified` as `IsExcluded` uses it: `::`, `0.0.0.0`, and the mapped form of the
/// latter.
pub fn is_unspecified(bytes: &[u8]) -> bool {
    match to4(bytes) {
        Some(v4) => v4 == [0, 0, 0, 0],
        None => bytes.len() == 16 && bytes.iter().all(|byte| *byte == 0),
    }
}

#[cfg(test)]
mod tests;

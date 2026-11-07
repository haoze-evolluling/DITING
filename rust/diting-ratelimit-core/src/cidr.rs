//! `net.ParseCIDR` and `IPNet.Contains`, including the two v4-mapped corner cases.
//!
//! The Go limiter parsed each exemption once with `net.ParseCIDR` and then asked
//! `(*net.IPNet).Contains` on every request. Both halves are reproduced here:
//!
//! * the prefix text is decimal digits only (Go's `dtoi`), so `08` is accepted and `+8` is not;
//! * the address half is `parseIPv4` then `parseIPv6`, so leading zeros are rejected;
//! * `networkNumberAndMask` collapses a v4-mapped network to four bytes and then trims a 16-byte
//!   mask to its last four bytes. That makes `::ffff:10.0.0.0/120` behave like `10.0.0.0/24`
//!   and `::ffff:10.0.0.0/96` behave like `0.0.0.0/0` over IPv4 addresses. This is counter-
//!   intuitive, but it is what the Go implementation did, and the fixture pins it.
//!
//! IPv6 exemption entries carry their own width, so `::/0` never matches an IPv4 client (the
//! families are different lengths); only the mapped-network collapse crosses families.

use std::net::{Ipv4Addr, Ipv6Addr};

use crate::ip::Addr;

/// One parsed exemption network, already normalised the way `IPNet.Contains` compares.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Cidr {
    /// The masked network, collapsed to four bytes when it started as a v4-mapped address.
    network: Addr,
    /// Bit count over [`Cidr::network`]'s width.
    prefix: u8,
}

impl Cidr {
    /// `net.ParseCIDR`.
    pub fn parse(text: &str) -> Option<Self> {
        let slash = text.find('/')?;
        let (address, mask) = (&text[..slash], &text[slash + 1..]);

        let (raw, width) = if let Ok(address) = address.parse::<Ipv4Addr>() {
            (Addr::V4(address.octets()), 32u32)
        } else {
            let address = address.parse::<Ipv6Addr>().ok()?;
            (Addr::V6(address.octets()), 128u32)
        };

        // `dtoi`: at least one digit, digits only, and it must fit the family.
        if mask.is_empty() || !mask.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        let prefix: u32 = mask.parse().ok()?;
        if prefix > width {
            return None;
        }

        let masked = raw.masked(prefix as u8);
        Some(match masked {
            // `networkNumberAndMask`: a network that still looks like ::ffff:a.b.c.d is compared
            // as four bytes with the low four bytes of the mask, i.e. prefix - 96.
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

    /// `(*net.IPNet).Contains`.
    ///
    /// The address is already collapsed by [`Addr`], so a v4-mapped client compares as IPv4 on
    /// both sides. A family mismatch is false, exactly like the Go length check.
    pub fn contains(&self, address: &Addr) -> bool {
        // `networkNumberAndMask` compares the length first: an IPv4 client never reaches an IPv6
        // network, not even through a prefix that would be out of range for four bytes.
        if address.width() != self.network.width() {
            return false;
        }
        address.masked(self.prefix) == self.network
    }
}

/// The `::ffff:a.b.c.d` shape Go's `To4` collapses.
fn is_v4_mapped(raw: &[u8; 16]) -> bool {
    raw[..10].iter().all(|byte| *byte == 0) && raw[10] == 0xff && raw[11] == 0xff
}

#[cfg(test)]
mod tests;

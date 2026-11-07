//! `net.IP` as the rate limiter observed it.
//!
//! The Go implementation called `To4()` before every map lookup, so a 16-byte
//! `::ffff:a.b.c.d` and the 4-byte `a.b.c.d` were the same client. [`Addr`] keeps that collapse at
//! the boundary: it is either four or sixteen bytes, and the mapped form never survives as a
//! separate value. The exemption map and the bucket keys both compare these bytes, which is why
//! this crate never has to agree with Go about IPv6 text formatting.
//!
//! `parse` is `net.ParseIP`'s accept/reject set limited to the forms that reach it: a plain IPv4
//! literal or an IPv6 literal (including the embedded-IPv4 tail). Zones (`fe80::1%eth0`) are
//! rejected on both sides. The corpus fixture pins the exact outcomes the Go implementation had.

use std::net::{Ipv4Addr, Ipv6Addr};

/// One address after Go's `To4` collapse.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Addr {
    /// Four bytes, either a genuine IPv4 literal or a `::ffff:a.b.c.d` that collapsed.
    V4([u8; 4]),
    /// Sixteen bytes that are not `::ffff:a.b.c.d`.
    V6([u8; 16]),
}

impl Addr {
    /// Reads the bytes of a `net.IP`: 4 or 16, with `To4` applied.
    ///
    /// Returns `None` for any other width — `net.IP` normally only holds those two, and the ABI
    /// treats an unusable width as a caller bug.
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

    /// `net.ParseIP` for the shapes the limiter sees.
    ///
    /// Go dispatches on the first `.` or `:`, which only matters for strings that are invalid in
    /// both branches; matching the outcome is enough here. The corpus fixture covers both branches,
    /// including leading zeros and IPv4 tails.
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

    /// Builds the collapsed form of a 16-byte address.
    fn from_v6(raw: [u8; 16]) -> Self {
        if raw[..10].iter().all(|byte| *byte == 0) && raw[10] == 0xff && raw[11] == 0xff {
            return Addr::V4([raw[12], raw[13], raw[14], raw[15]]);
        }
        Addr::V6(raw)
    }

    /// Width in bytes: 4 or 16.
    pub fn width(&self) -> usize {
        match self {
            Addr::V4(_) => 4,
            Addr::V6(_) => 16,
        }
    }

    /// The bytes this address compares as.
    pub fn as_bytes(&self) -> &[u8] {
        match self {
            Addr::V4(bytes) => bytes,
            Addr::V6(bytes) => bytes,
        }
    }

    /// `net.IP.Mask` with a prefix length in bits, within this address's own width.
    ///
    /// The caller passes a normalised prefix (`0..=32` for IPv4, `0..=128` for IPv6); a wider
    /// prefix would mean the caller skipped normalisation, which the parser and limiter never do.
    pub fn masked(&self, prefix: u8) -> Addr {
        let width_bits = self.width() * 8;
        debug_assert!(usize::from(prefix) <= width_bits);
        match *self {
            Addr::V4(bytes) => Addr::V4(mask_bytes(bytes, prefix)),
            Addr::V6(bytes) => Addr::V6(mask_bytes(bytes, prefix)),
        }
    }
}

/// Applies a contiguous bit mask to `bytes` in place.
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

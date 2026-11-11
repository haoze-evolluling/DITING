//! Address parsing with Go's `net.IP` semantics.
//!
//! The old parser called `net.ParseIP` and then asked `ip.To4()` twice: once to decide whether the
//! entry belongs in the IPv4 map, once to store the 4-byte form. Every address this kernel hands
//! back is therefore already collapsed — `::ffff:1.2.3.4` is IPv4, not a 16-byte IPv6 address with
//! an embedded quad. The reverse map is keyed by the same collapsed value instead of by
//! `ip.String()`, which is equivalent (Go's `String()` prints the mapped form as a dotted quad) and
//! does not depend on two formatters agreeing on compression.
//!
//! Where Rust and Go disagree about what a valid address literal looks like, the corpus in
//! `tests/fixtures/expectations.tsv` (generated from the Go implementation before it was deleted)
//! is what decides. The one structural difference is that Go's parser is strict about leading
//! zeros in dotted quads and Rust's is too, so the two agree there.

use std::net::{Ipv4Addr, Ipv6Addr};

/// A parsed address, collapsed the way `net.IP.To4` collapses an IPv4-mapped IPv6 address.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Addr {
    /// 4 bytes, the form `net.IP.To4()` returns.
    V4([u8; 4]),
    /// 16 bytes, everything else.
    V6([u8; 16]),
}

impl Addr {
    /// `4` or `16`.
    pub fn width(&self) -> usize {
        match self {
            Addr::V4(_) => 4,
            Addr::V6(_) => 16,
        }
    }

    /// The bytes, 4 or 16 depending on the family.
    pub fn as_bytes(&self) -> &[u8] {
        match self {
            Addr::V4(bytes) => bytes,
            Addr::V6(bytes) => bytes,
        }
    }

    /// Reads back what [`Addr::as_bytes`] wrote; `None` for any length other than 4 / 16.
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

/// `net.ParseIP` followed by the `To4` collapse.
///
/// `::ffff:1.2.3.4` and `0:0:0:0:0:ffff:1.2.3.4` are the same IPv4 address, exactly like Go's
/// `To4`; `::1.2.3.4` (which is not mapped) keeps its 16 bytes.
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

/// One hosts entry's address: the interface zone (`fe80::1%eth0`) is cut off at the first `%`
/// before parsing, exactly like the Go parser did.
pub fn parse_hosts_address(raw: &str) -> Option<Addr> {
    let raw = match raw.find('%') {
        Some(index) => &raw[..index],
        None => raw,
    };
    parse_ip(raw)
}

/// Collapses an IPv6 literal to IPv4 when it is the mapped form.
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

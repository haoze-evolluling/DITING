//! Go `net.IP` semantics over raw address bytes.
//!
//! The kernels receive addresses as the bytes a DNS record carried, so the Go behaviour has to be
//! reproduced byte for byte: `net.IP.String()` (dotted quad, IPv4-mapped folding, `netip`'s
//! zero-run rules, `"?"` + hex for a body that is not 4 or 16 bytes, `"<nil>"` for an empty one),
//! `To4`, `IsLoopback` and equality against `net.IPv4zero` / `net.IPv6zero`.
//!
//! `net.IPv4zero` is the 16-byte `::ffff:0.0.0.0` form, which is why a 4-byte `0.0.0.0` record and
//! its mapped form compare equal to it while a plain 16-byte `::` does not. That asymmetry decides
//! "is this answer a null block" in `diting-dns-core`, so it is spelled out here.

use std::fmt::Write as _;

/// `net.IPv4zero` in its 16-byte form: `::ffff:0.0.0.0`.
const V4_IN_V6_PREFIX: [u8; 12] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff];

/// `net.IP.To4`: a 4-byte body, or a 16-byte IPv4-mapped body folded to its last four bytes.
pub fn to4(bytes: &[u8]) -> Option<[u8; 4]> {
    match bytes.len() {
        4 => Some([bytes[0], bytes[1], bytes[2], bytes[3]]),
        16 if bytes[..12] == V4_IN_V6_PREFIX => Some([bytes[12], bytes[13], bytes[14], bytes[15]]),
        _ => None,
    }
}

/// `net.IP.IsLoopback`: `127.0.0.0/8` after the IPv4 fold, else `::1`.
pub fn is_loopback(bytes: &[u8]) -> bool {
    match to4(bytes) {
        Some(v4) => v4[0] == 127,
        None => bytes.len() == 16 && bytes[..15].iter().all(|byte| *byte == 0) && bytes[15] == 1,
    }
}

/// `ip.Equal(net.IPv4zero)`.
pub fn equals_ipv4_zero(bytes: &[u8]) -> bool {
    match bytes.len() {
        4 => bytes.iter().all(|byte| *byte == 0),
        16 => bytes[..12] == V4_IN_V6_PREFIX && bytes[12..].iter().all(|byte| *byte == 0),
        _ => false,
    }
}

/// `ip.Equal(net.IPv6zero)`: only a 16-byte all-zero body. A 4-byte `0.0.0.0` does *not* equal
/// `::`, because `Equal` with mismatched lengths compares against the v4-in-v6 prefix.
pub fn equals_ipv6_zero(bytes: &[u8]) -> bool {
    bytes.len() == 16 && bytes.iter().all(|byte| *byte == 0)
}

/// `net.IP.String()`.
pub fn go_ip_string(bytes: &[u8]) -> String {
    match bytes.len() {
        0 => "<nil>".to_string(),
        4 => dotted(&[bytes[0], bytes[1], bytes[2], bytes[3]]),
        16 => match to4(bytes) {
            Some(v4) => dotted(&v4),
            None => ipv6(bytes),
        },
        _ => {
            let mut text = String::with_capacity(1 + bytes.len() * 2);
            text.push('?');
            for byte in bytes {
                text.push(hex_digit(byte >> 4));
                text.push(hex_digit(byte & 0x0f));
            }
            text
        }
    }
}

fn hex_digit(value: u8) -> char {
    match value {
        0..=9 => (b'0' + value) as char,
        _ => (b'a' + value - 10) as char,
    }
}

fn dotted(bytes: &[u8; 4]) -> String {
    format!("{}.{}.{}.{}", bytes[0], bytes[1], bytes[2], bytes[3])
}

/// `netip.Addr`'s IPv6 text: the leftmost longest run of at least two zero segments becomes `::`,
/// segments print as lowercase hex without leading zeros, and nothing else is shortened.
fn ipv6(bytes: &[u8]) -> String {
    let mut segments = [0u16; 8];
    for (index, segment) in segments.iter_mut().enumerate() {
        *segment = u16::from_be_bytes([bytes[index * 2], bytes[index * 2 + 1]]);
    }

    let mut zero_run: Option<(usize, usize)> = None;
    for start in 0..8 {
        let mut end = start;
        while end < 8 && segments[end] == 0 {
            end += 1;
        }
        if end - start < 2 {
            continue;
        }
        let longer = match zero_run {
            None => true,
            Some((best_start, best_end)) => end - start > best_end - best_start,
        };
        if longer {
            zero_run = Some((start, end));
        }
    }

    let mut text = String::with_capacity(39);
    let mut index = 0;
    while index < 8 {
        if let Some((start, end)) = zero_run {
            if index == start {
                text.push_str("::");
                index = end;
                if index >= 8 {
                    break;
                }
            } else if index > 0 {
                text.push(':');
            }
        } else if index > 0 {
            text.push(':');
        }
        let _ = write!(text, "{:x}", segments[index]);
        index += 1;
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn to4_folds_only_the_mapped_prefix() {
        assert_eq!(to4(&[1, 2, 3, 4]), Some([1, 2, 3, 4]));
        assert_eq!(to4(&[0, 0, 0, 0]), Some([0, 0, 0, 0]));
        let mut mapped = [0u8; 16];
        mapped[10] = 0xff;
        mapped[11] = 0xff;
        mapped[12..].copy_from_slice(&[9, 8, 7, 6]);
        assert_eq!(to4(&mapped), Some([9, 8, 7, 6]));
        // The prefix must be exactly the mapped one.
        let mut wrong = mapped;
        wrong[9] = 1;
        assert_eq!(to4(&wrong), None);
        assert_eq!(to4(&[0u8; 16]), None);
        assert_eq!(to4(&[]), None);
        assert_eq!(to4(&[1, 2, 3, 4, 5]), None);
    }

    #[test]
    fn zero_equality_matches_the_go_constants() {
        assert!(equals_ipv4_zero(&[0, 0, 0, 0]));
        assert!(equals_ipv4_zero(&{
            let mut mapped = [0u8; 16];
            mapped[10] = 0xff;
            mapped[11] = 0xff;
            mapped
        }));
        assert!(!equals_ipv4_zero(&[0u8; 16]), ":: is not net.IPv4zero");
        assert!(equals_ipv6_zero(&[0u8; 16]));
        assert!(
            !equals_ipv6_zero(&[0, 0, 0, 0]),
            "0.0.0.0 is not net.IPv6zero"
        );
    }

    #[test]
    fn loopback_covers_the_v4_prefix_and_v6_loopback() {
        assert!(is_loopback(&[127, 0, 0, 1]));
        assert!(is_loopback(&[127, 255, 255, 255]));
        assert!(!is_loopback(&[126, 0, 0, 1]));
        let mut loopback6 = [0u8; 16];
        loopback6[15] = 1;
        assert!(is_loopback(&loopback6));
        let mut not_loopback6 = loopback6;
        not_loopback6[14] = 1;
        assert!(!is_loopback(&not_loopback6));
    }

    #[test]
    fn string_covers_nil_mapped_and_malformed_bodies() {
        assert_eq!(go_ip_string(&[]), "<nil>");
        assert_eq!(go_ip_string(&[1, 2, 3, 4]), "1.2.3.4");
        assert_eq!(go_ip_string(&[1, 2, 3, 4, 5]), "?0102030405");
        assert_eq!(go_ip_string(&[0u8; 16]), "::");
        assert_eq!(
            go_ip_string(&[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
            "::1"
        );
    }
}

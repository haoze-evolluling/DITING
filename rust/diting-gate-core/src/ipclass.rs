//! `isLoopbackOrInternal` and the `net.IP` predicates it used.
//!
//! The flow handlers only ever pass `flow.serverIP` (raw 4/16 bytes), so this works on bytes and
//! folds IPv4-mapped addresses through `To4` exactly like `net.IPNet.Contains` / `net.IP.IsLoopback`
//! did. The hostname branches of the old helper (`localhost`, `0.0.0.0`, `::`) are the same
//! addresses after parsing and are covered by the unspecified / loopback tests.

use diting_go_compat::ip::{is_loopback, to4};

/// `net.IP.IsUnspecified`: `0.0.0.0` or `::`.
pub fn is_unspecified(bytes: &[u8]) -> bool {
    match to4(bytes) {
        Some(v4) => v4 == [0, 0, 0, 0],
        None => bytes.len() == 16 && bytes.iter().all(|byte| *byte == 0),
    }
}

/// `net.IP.IsLinkLocalUnicast`: `169.254.0.0/16` or `fe80::/10`.
pub fn is_link_local_unicast(bytes: &[u8]) -> bool {
    match to4(bytes) {
        Some(v4) => v4[0] == 169 && v4[1] == 254,
        None => bytes.len() == 16 && bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80,
    }
}

/// `isPrivateIP`: the RFC 1918 ranges, after the IPv4 fold.
pub fn is_private_ip(bytes: &[u8]) -> bool {
    let Some(v4) = to4(bytes) else {
        return false;
    };
    match v4[0] {
        10 => true,
        172 => (16..=31).contains(&v4[1]),
        192 => v4[1] == 168,
        _ => false,
    }
}

/// `isLoopbackOrInternal(ip)`: loopback, unspecified, link-local unicast or RFC 1918.
pub fn is_loopback_or_internal(bytes: &[u8]) -> bool {
    is_loopback(bytes)
        || is_unspecified(bytes)
        || is_link_local_unicast(bytes)
        || is_private_ip(bytes)
}

/// `isTLSClientPort`: the ports `relayDirectFromFlow` peeks for SNI on an IPv6 path.
pub fn is_tls_client_port(port: u16) -> bool {
    matches!(port, 443 | 465 | 993 | 8443)
}

#[cfg(test)]
mod tests;

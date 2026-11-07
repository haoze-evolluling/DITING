//! Go `net` helpers: address parsing and text, host/port splitting.
//!
//! Three kernels now need the same four functions, so they live here rather than in the crate that
//! happened to migrate first (the outbound proxy). The old Go code called `net.ParseIP`,
//! `net.SplitHostPort`, `net.JoinHostPort` and `net.IP.String` on config hosts, dial targets and
//! DNS endpoints, so those four have to keep Go's exact accept/reject set and text shape:
//!
//! * [`parse_ip`] is `net.ParseIP`: a dotted-quad becomes the 16-byte `::ffff:` form, an IPv6
//!   literal becomes its 16 bytes, a scoped literal (`fe80::1%eth0`) or a hostname is `None`.
//! * [`split_host_port`] is `net.SplitHostPort`, including the `address ...: <reason>` text of the
//!   `*net.AddrError` it returns and the empty-address case (no `address` prefix).
//! * [`join_host_port`] brackets a host that contains a colon.
//! * [`ip_text`] is `net.IP.String`, taken from [`crate::ip`].

use crate::ip as go_ip;

/// `net.ParseIP`: 16 bytes, with IPv4 in its IPv4-mapped form, or `None`.
pub fn parse_ip(text: &str) -> Option<[u8; 16]> {
    if let Ok(v4) = text.parse::<std::net::Ipv4Addr>() {
        let mut out = [0u8; 16];
        out[10] = 0xff;
        out[11] = 0xff;
        out[12..].copy_from_slice(&v4.octets());
        return Some(out);
    }
    text.parse::<std::net::Ipv6Addr>()
        .ok()
        .map(|v6| v6.octets())
}

/// `net.IP.To4` over the bytes [`parse_ip`] produced.
pub fn to4(bytes: &[u8]) -> Option<[u8; 4]> {
    go_ip::to4(bytes)
}

/// `net.IP.IsLoopback`.
pub fn is_loopback(bytes: &[u8]) -> bool {
    go_ip::is_loopback(bytes)
}

/// `net.IP.String`.
pub fn ip_text(bytes: &[u8]) -> String {
    go_ip::go_ip_string(bytes)
}

/// `net.JoinHostPort` with a numeric port.
pub fn join_host_port(host: &str, port: u16) -> String {
    if host.as_bytes().contains(&b':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

const MISSING_PORT: &str = "missing port in address";
const TOO_MANY_COLONS: &str = "too many colons in address";

/// `net.SplitHostPort`: host and port, or the `*net.AddrError` text (`address <addr>: <reason>`).
pub fn split_host_port(hostport: &str) -> Result<(&str, &str), String> {
    let bytes = hostport.as_bytes();
    let fail = |reason: &str| -> Result<(&str, &str), String> { Err(addr_error(hostport, reason)) };

    // The port starts after the last colon.
    let Some(index) = hostport.rfind(':') else {
        return fail(MISSING_PORT);
    };

    let (host_start, host_end) = if bytes[0] == b'[' {
        // Expect the first ']' just before the last ':'.
        let Some(end) = hostport.find(']') else {
            return fail("missing ']' in address");
        };
        if end + 1 == bytes.len() {
            return fail(MISSING_PORT);
        }
        if end + 1 != index {
            return if bytes[end + 1] == b':' {
                fail(TOO_MANY_COLONS)
            } else {
                fail(MISSING_PORT)
            };
        }
        (1, end)
    } else {
        if bytes[..index].contains(&b':') {
            return fail(TOO_MANY_COLONS);
        }
        (0, index)
    };

    // The bracket scan windows Go checks after picking the host: `hostport[j:]` may not hold a
    // '[' and `hostport[k:]` may not hold a ']'.
    let bracket_from = if host_start == 1 { 1 } else { 0 };
    let close_from = if host_start == 1 { host_end + 1 } else { 0 };
    if bytes[bracket_from..].contains(&b'[') {
        return fail("unexpected '[' in address");
    }
    if bytes[close_from..].contains(&b']') {
        return fail("unexpected ']' in address");
    }

    Ok((&hostport[host_start..host_end], &hostport[index + 1..]))
}

/// The text of `&net.AddrError{Err: reason, Addr: addr}` (`Error()` omits the prefix for an empty
/// address).
fn addr_error(addr: &str, reason: &str) -> String {
    if addr.is_empty() {
        reason.to_string()
    } else {
        format!("address {addr}: {reason}")
    }
}

#[cfg(test)]
mod tests;

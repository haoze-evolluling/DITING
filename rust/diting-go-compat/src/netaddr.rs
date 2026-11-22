use crate::ip as go_ip;

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

pub fn to4(bytes: &[u8]) -> Option<[u8; 4]> {
    go_ip::to4(bytes)
}

pub fn is_loopback(bytes: &[u8]) -> bool {
    go_ip::is_loopback(bytes)
}

pub fn ip_text(bytes: &[u8]) -> String {
    go_ip::go_ip_string(bytes)
}

pub fn join_host_port(host: &str, port: u16) -> String {
    join_host_port_text(host, &port.to_string())
}

pub fn join_host_port_text(host: &str, port: &str) -> String {
    if host.as_bytes().contains(&b':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

const MISSING_PORT: &str = "missing port in address";
const TOO_MANY_COLONS: &str = "too many colons in address";

pub fn split_host_port(hostport: &str) -> Result<(&str, &str), String> {
    let bytes = hostport.as_bytes();
    let fail = |reason: &str| -> Result<(&str, &str), String> { Err(addr_error(hostport, reason)) };

    let Some(index) = hostport.rfind(':') else {
        return fail(MISSING_PORT);
    };

    let (host_start, host_end) = if bytes[0] == b'[' {
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

fn addr_error(addr: &str, reason: &str) -> String {
    if addr.is_empty() {
        reason.to_string()
    } else {
        format!("address {addr}: {reason}")
    }
}

#[cfg(test)]
mod tests;

//! The SOCKS5 wire codec: greeting, method/auth exchange, request address encoding, reply parsing
//! and the UDP-associate datagram framing.
//!
//! Go keeps the socket: it writes what [`greeting`] / [`auth_request`] / [`request`] return, reads
//! exactly the sizes the replies declare and hands the bytes back here. That split is what keeps
//! the deadlines, the `net.Conn` type and the status reporting unchanged.
//!
//! Behaviour copied from the pre-migration `flow_outbound.go`, quirks included:
//!
//! * the greeting only offers username/password when a username *or* a password is set;
//! * `method_reply` rejects a reply whose first byte is not `0x05` instead of reading a method;
//! * `auth_reply` only looks at the status byte, never at the sub-negotiation version;
//! * a reply whose status byte is non-zero fails with that byte as the code (`0` for a bad
//!   version), and a domain-shaped relay host may be anything, even empty;
//! * the address encoder treats a non-IP host as a domain, including literals Go rejects such as
//!   `1.2.3.4.5` or a scoped `fe80::1%eth0`.

use crate::addr::{ip_text, join_host_port, parse_ip, split_host_port, to4};

/// SOCKS5 `CONNECT`.
pub const COMMAND_CONNECT: u8 = 0x01;
/// SOCKS5 `UDP ASSOCIATE`.
pub const COMMAND_UDP_ASSOCIATE: u8 = 0x03;

/// The authentication method the proxy picked.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthMethod {
    None,
    UserPass,
}

impl AuthMethod {
    /// Wire value of the "selected method" byte.
    pub fn code(self) -> u8 {
        match self {
            AuthMethod::None => 0x00,
            AuthMethod::UserPass => 0x02,
        }
    }
}

/// Result of [`parse_reply`]: either the relay endpoint or how many bytes the frame needs in total.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReplyParse {
    Done { address: String },
    NeedMore(usize),
}

/// One decoded UDP-associate datagram: the remote endpoint and the payload after the header.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DatagramView {
    pub address: String,
    pub host_is_ip: bool,
    /// Offset of the payload inside the bytes the caller passed in.
    pub offset: usize,
}

/// The greeting: version, method count and the offered methods.
pub fn greeting(username: &str, password: &str) -> Vec<u8> {
    let mut methods = vec![0x00];
    if !username.is_empty() || !password.is_empty() {
        methods.push(0x02);
    }
    let mut out = Vec::with_capacity(2 + methods.len());
    out.push(0x05);
    out.push(methods.len() as u8);
    out.extend_from_slice(&methods);
    out
}

/// Reads the proxy's method selection (two bytes: version + selected method).
pub fn method_reply(reply: &[u8]) -> Result<AuthMethod, String> {
    if reply.len() != 2 || reply[0] != 0x05 {
        return Err("invalid SOCKS5 greeting response".to_string());
    }
    match reply[1] {
        0xff => Err("SOCKS5 proxy rejected authentication methods".to_string()),
        0x02 => Ok(AuthMethod::UserPass),
        0x00 => Ok(AuthMethod::None),
        other => Err(format!("unsupported SOCKS5 authentication method {other}")),
    }
}

/// The RFC 1929 username/password sub-negotiation request.
pub fn auth_request(username: &str, password: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(3 + username.len() + password.len());
    out.push(0x01);
    out.push(username.len() as u8);
    out.extend_from_slice(username.as_bytes());
    out.push(password.len() as u8);
    out.extend_from_slice(password.as_bytes());
    out
}

/// Reads the sub-negotiation reply: only the status byte decides, as before.
pub fn auth_reply(reply: &[u8]) -> Result<(), String> {
    if reply.len() != 2 || reply[1] != 0x00 {
        return Err("SOCKS5 authentication failed".to_string());
    }
    Ok(())
}

/// Encodes `host:port` as ATYP + address + port.
pub fn address(target: &str) -> Result<Vec<u8>, String> {
    let (host, port_text) =
        split_host_port(target).map_err(|err| format!("invalid target {target:?}: {err}"))?;
    let port = match port_text.parse::<i64>() {
        Ok(port) if (0..=65535).contains(&port) => port as u16,
        _ => return Err(format!("invalid target port {port_text:?}")),
    };

    let mut out = Vec::with_capacity(1 + 16 + 2);
    match parse_ip(host) {
        Some(bytes) => match to4(&bytes) {
            Some(v4) => {
                out.push(0x01);
                out.extend_from_slice(&v4);
            }
            None => {
                out.push(0x04);
                out.extend_from_slice(&bytes);
            }
        },
        None => {
            if host.is_empty() || host.len() > 255 {
                return Err("SOCKS5 target hostname length is invalid".to_string());
            }
            out.push(0x03);
            out.push(host.len() as u8);
            out.extend_from_slice(host.as_bytes());
        }
    }
    out.extend_from_slice(&port.to_be_bytes());
    Ok(out)
}

/// The full request: version, command, reserved byte and the encoded address.
pub fn request(command: u8, target: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(3 + 1 + 16 + 2);
    out.extend_from_slice(&[0x05, command, 0x00]);
    out.extend_from_slice(&address(target)?);
    Ok(out)
}

/// The fixed `UDP ASSOCIATE` request for `0.0.0.0:0` (the relay picks the address).
pub fn udp_associate_request() -> Vec<u8> {
    vec![0x05, COMMAND_UDP_ASSOCIATE, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
}

/// Parses a reply frame, asking for more bytes while the frame is incomplete.
///
/// The checks run in the order the old reader ran them: the header (including the status byte) is
/// validated as soon as four bytes are in, before the address is read.
pub fn parse_reply(buf: &[u8]) -> Result<ReplyParse, String> {
    if buf.len() < 4 {
        return Ok(ReplyParse::NeedMore(4));
    }
    if buf[0] != 0x05 || buf[1] != 0x00 {
        return Err(format!("SOCKS5 request failed with code {}", buf[1]));
    }
    let (host, cursor) = match buf[3] {
        0x01 => {
            if buf.len() < 4 + 4 + 2 {
                return Ok(ReplyParse::NeedMore(4 + 4 + 2));
            }
            (ip_text(&buf[4..8]), 8)
        }
        0x04 => {
            if buf.len() < 4 + 16 + 2 {
                return Ok(ReplyParse::NeedMore(4 + 16 + 2));
            }
            (ip_text(&buf[4..20]), 20)
        }
        0x03 => {
            if buf.len() < 5 {
                return Ok(ReplyParse::NeedMore(5));
            }
            let length = usize::from(buf[4]);
            let total = 5 + length + 2;
            if buf.len() < total {
                return Ok(ReplyParse::NeedMore(total));
            }
            (
                String::from_utf8_lossy(&buf[5..5 + length]).into_owned(),
                5 + length,
            )
        }
        other => return Err(format!("invalid SOCKS5 address type {other}")),
    };
    let port = u16::from_be_bytes([buf[cursor], buf[cursor + 1]]);
    Ok(ReplyParse::Done {
        address: join_host_port(&host, port),
    })
}

/// Wraps a payload into `RSV(0) | address | payload`.
pub fn datagram(target: &str, payload: &[u8]) -> Result<Vec<u8>, String> {
    let address = address(target)?;
    let mut out = Vec::with_capacity(3 + address.len() + payload.len());
    out.extend_from_slice(&[0x00, 0x00, 0x00]);
    out.extend_from_slice(&address);
    out.extend_from_slice(payload);
    Ok(out)
}

/// Parses the datagram bytes that follow the three reserved bytes.
///
/// The caller has already validated the reserved header and passes exactly `buf[3:n]`, so a short
/// buffer is a truncated datagram: the errors are Go's `io` texts (`EOF` when nothing was left,
/// `unexpected EOF` when a field was cut short).
pub fn parse_datagram(buf: &[u8]) -> Result<DatagramView, String> {
    let mut cursor = 0;
    let atyp = read_u8(buf, &mut cursor)?;
    let host = match atyp {
        0x01 => ip_text(read_field(buf, &mut cursor, 4)?.as_slice()),
        0x04 => ip_text(read_field(buf, &mut cursor, 16)?.as_slice()),
        0x03 => {
            let length = usize::from(read_u8(buf, &mut cursor)?);
            let start = cursor;
            read_field(buf, &mut cursor, length)?;
            String::from_utf8_lossy(&buf[start..start + length]).into_owned()
        }
        other => return Err(format!("invalid SOCKS5 address type {other}")),
    };
    let port_bytes = read_field(buf, &mut cursor, 2)?;
    let port = u16::from_be_bytes([port_bytes[0], port_bytes[1]]);
    Ok(DatagramView {
        address: join_host_port(&host, port),
        host_is_ip: parse_ip(&host).is_some(),
        offset: cursor,
    })
}

fn read_u8(buf: &[u8], cursor: &mut usize) -> Result<u8, String> {
    Ok(read_field(buf, cursor, 1)?[0])
}

/// `io.ReadFull` over a slice: `EOF` with nothing left, `unexpected EOF` with a partial field.
fn read_field(buf: &[u8], cursor: &mut usize, length: usize) -> Result<Vec<u8>, String> {
    let available = buf.len() - *cursor;
    if available < length {
        return Err(if available == 0 {
            "EOF"
        } else {
            "unexpected EOF"
        }
        .to_string());
    }
    let field = buf[*cursor..*cursor + length].to_vec();
    *cursor += length;
    Ok(field)
}

#[cfg(test)]
mod tests;

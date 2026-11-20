use crate::addr::{ip_text, join_host_port, parse_ip, split_host_port, to4};

pub const COMMAND_CONNECT: u8 = 0x01;
pub const COMMAND_UDP_ASSOCIATE: u8 = 0x03;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthMethod {
    None,
    UserPass,
}

impl AuthMethod {
    pub fn code(self) -> u8 {
        match self {
            AuthMethod::None => 0x00,
            AuthMethod::UserPass => 0x02,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReplyParse {
    Done { address: String },
    NeedMore(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DatagramView {
    pub address: String,
    pub host_is_ip: bool,
    pub offset: usize,
}

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

pub fn auth_request(username: &str, password: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(3 + username.len() + password.len());
    out.push(0x01);
    out.push(username.len() as u8);
    out.extend_from_slice(username.as_bytes());
    out.push(password.len() as u8);
    out.extend_from_slice(password.as_bytes());
    out
}

pub fn auth_reply(reply: &[u8]) -> Result<(), String> {
    if reply.len() != 2 || reply[1] != 0x00 {
        return Err("SOCKS5 authentication failed".to_string());
    }
    Ok(())
}

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

pub fn request(command: u8, target: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(3 + 1 + 16 + 2);
    out.extend_from_slice(&[0x05, command, 0x00]);
    out.extend_from_slice(&address(target)?);
    Ok(out)
}

pub fn udp_associate_request() -> Vec<u8> {
    vec![0x05, COMMAND_UDP_ASSOCIATE, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
}

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

pub fn datagram(target: &str, payload: &[u8]) -> Result<Vec<u8>, String> {
    let address = address(target)?;
    let mut out = Vec::with_capacity(3 + address.len() + payload.len());
    out.extend_from_slice(&[0x00, 0x00, 0x00]);
    out.extend_from_slice(&address);
    out.extend_from_slice(payload);
    Ok(out)
}

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

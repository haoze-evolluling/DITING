//! The binary layout shared with `android/engine/proxy_native_payload.go`.
//!
//! Request (Go -> kernel):
//!
//! ```text
//! | u8 layout | u8 op | body |
//! ```
//!
//! Response (kernel -> Go):
//!
//! ```text
//! | u8 status (0 ok, 1 error) | body |
//! ```
//!
//! `str` is `u32 length | bytes` (UTF-8 required), `bytes` is `u32 length | bytes`, ports and UIDs
//! are `i64` (Go's `int` is 64 bits wide, and the config accepts values outside 16/32 bits before
//! validation rejects them). A drifted version, a length that disagrees with the payload or
//! trailing bytes is a hard error, never a misread.
//!
//! | op | name | request body | ok body |
//! | --- | --- | --- | --- |
//! | 0 | configure | enabled, protocol, host, port, username, password, scope, uids | enabled, protocol, host, port, scope, uids |
//! | 1 | socks greeting | username, password | bytes |
//! | 2 | socks method reply | bytes | u8 method |
//! | 3 | socks auth | username, password | bytes |
//! | 4 | socks auth reply | bytes | (empty) |
//! | 5 | socks request | u8 command, target | bytes |
//! | 6 | socks udp associate | (empty) | bytes |
//! | 7 | socks reply | bytes | u8 kind, then address or needed |
//! | 8 | socks datagram | target, payload | bytes |
//! | 9 | socks datagram parse | bytes | address, u8 is_ip, u32 offset |
//! | 10 | http connect request | target, username, password | bytes |

use crate::config::{NormalizedConfig, ProxyConfig};
use crate::socks5::{self, ReplyParse};

/// Must match `proxyPayloadLayoutVersion` in `android/engine/proxy_native_payload.go`.
pub const LAYOUT_VERSION: u8 = 1;

/// Opcodes, in the order of the table above.
pub const OP_CONFIGURE: u8 = 0;
pub const OP_SOCKS_GREETING: u8 = 1;
pub const OP_SOCKS_METHOD_REPLY: u8 = 2;
pub const OP_SOCKS_AUTH: u8 = 3;
pub const OP_SOCKS_AUTH_REPLY: u8 = 4;
pub const OP_SOCKS_REQUEST: u8 = 5;
pub const OP_SOCKS_UDP_ASSOCIATE: u8 = 6;
pub const OP_SOCKS_REPLY: u8 = 7;
pub const OP_SOCKS_DATAGRAM: u8 = 8;
pub const OP_SOCKS_DATAGRAM_PARSE: u8 = 9;
pub const OP_HTTP_CONNECT: u8 = 10;

const STATUS_OK: u8 = 0;
const STATUS_ERROR: u8 = 1;

/// One decoded request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    Configure(ProxyConfig),
    SocksGreeting {
        username: String,
        password: String,
    },
    SocksMethodReply {
        reply: Vec<u8>,
    },
    SocksAuth {
        username: String,
        password: String,
    },
    SocksAuthReply {
        reply: Vec<u8>,
    },
    SocksRequest {
        command: u8,
        target: String,
    },
    SocksUdpAssociate,
    SocksReply {
        frame: Vec<u8>,
    },
    SocksDatagram {
        target: String,
        payload: Vec<u8>,
    },
    SocksDatagramParse {
        datagram: Vec<u8>,
    },
    HttpConnect {
        target: String,
        username: String,
        password: String,
    },
}

/// The body of a successful response.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    Configured(NormalizedConfig),
    Bytes(Vec<u8>),
    Method(u8),
    Unit,
    Reply(ReplyParse),
    Datagram {
        address: String,
        host_is_ip: bool,
        offset: usize,
    },
}

/// Reads a request payload.
pub fn decode_request(payload: &[u8]) -> Option<Request> {
    let mut reader = Reader::new(payload);
    if reader.u8()? != LAYOUT_VERSION {
        return None;
    }
    let op = reader.u8()?;
    let request = match op {
        OP_CONFIGURE => Request::Configure(ProxyConfig {
            enabled: reader.u8()? != 0,
            protocol: reader.text()?,
            host: reader.text()?,
            port: reader.i64()?,
            username: reader.text()?,
            password: reader.text()?,
            scope: reader.text()?,
            uids: reader.i64_list()?,
        }),
        OP_SOCKS_GREETING => Request::SocksGreeting {
            username: reader.text()?,
            password: reader.text()?,
        },
        OP_SOCKS_METHOD_REPLY => Request::SocksMethodReply {
            reply: reader.bytes()?,
        },
        OP_SOCKS_AUTH => Request::SocksAuth {
            username: reader.text()?,
            password: reader.text()?,
        },
        OP_SOCKS_AUTH_REPLY => Request::SocksAuthReply {
            reply: reader.bytes()?,
        },
        OP_SOCKS_REQUEST => Request::SocksRequest {
            command: reader.u8()?,
            target: reader.text()?,
        },
        OP_SOCKS_UDP_ASSOCIATE => Request::SocksUdpAssociate,
        OP_SOCKS_REPLY => Request::SocksReply {
            frame: reader.bytes()?,
        },
        OP_SOCKS_DATAGRAM => Request::SocksDatagram {
            target: reader.text()?,
            payload: reader.bytes()?,
        },
        OP_SOCKS_DATAGRAM_PARSE => Request::SocksDatagramParse {
            datagram: reader.bytes()?,
        },
        OP_HTTP_CONNECT => Request::HttpConnect {
            target: reader.text()?,
            username: reader.text()?,
            password: reader.text()?,
        },
        _ => return None,
    };
    if !reader.at_end() {
        return None;
    }
    Some(request)
}

/// Writes a request payload (used by the tests and the corpus replayer).
pub fn encode_request(request: &Request) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    match request {
        Request::Configure(config) => {
            out.push(OP_CONFIGURE);
            out.push(u8::from(config.enabled));
            push_text(&mut out, &config.protocol);
            push_text(&mut out, &config.host);
            out.extend_from_slice(&config.port.to_le_bytes());
            push_text(&mut out, &config.username);
            push_text(&mut out, &config.password);
            push_text(&mut out, &config.scope);
            out.extend_from_slice(&(config.uids.len() as u32).to_le_bytes());
            for uid in &config.uids {
                out.extend_from_slice(&uid.to_le_bytes());
            }
        }
        Request::SocksGreeting { username, password }
        | Request::SocksAuth { username, password } => {
            out.push(if matches!(request, Request::SocksGreeting { .. }) {
                OP_SOCKS_GREETING
            } else {
                OP_SOCKS_AUTH
            });
            push_text(&mut out, username);
            push_text(&mut out, password);
        }
        Request::SocksMethodReply { reply } => {
            out.push(OP_SOCKS_METHOD_REPLY);
            push_bytes(&mut out, reply);
        }
        Request::SocksAuthReply { reply } => {
            out.push(OP_SOCKS_AUTH_REPLY);
            push_bytes(&mut out, reply);
        }
        Request::SocksRequest { command, target } => {
            out.push(OP_SOCKS_REQUEST);
            out.push(*command);
            push_text(&mut out, target);
        }
        Request::SocksUdpAssociate => out.push(OP_SOCKS_UDP_ASSOCIATE),
        Request::SocksReply { frame } => {
            out.push(OP_SOCKS_REPLY);
            push_bytes(&mut out, frame);
        }
        Request::SocksDatagram { target, payload } => {
            out.push(OP_SOCKS_DATAGRAM);
            push_text(&mut out, target);
            push_bytes(&mut out, payload);
        }
        Request::SocksDatagramParse { datagram } => {
            out.push(OP_SOCKS_DATAGRAM_PARSE);
            push_bytes(&mut out, datagram);
        }
        Request::HttpConnect {
            target,
            username,
            password,
        } => {
            out.push(OP_HTTP_CONNECT);
            push_text(&mut out, target);
            push_text(&mut out, username);
            push_text(&mut out, password);
        }
    }
    out
}

/// Runs one decoded request.
pub fn handle(request: Request) -> Result<Response, String> {
    match request {
        Request::Configure(config) => crate::config::normalize(config).map(Response::Configured),
        Request::SocksGreeting { username, password } => {
            Ok(Response::Bytes(socks5::greeting(&username, &password)))
        }
        Request::SocksMethodReply { reply } => {
            socks5::method_reply(&reply).map(|method| Response::Method(method.code()))
        }
        Request::SocksAuth { username, password } => {
            Ok(Response::Bytes(socks5::auth_request(&username, &password)))
        }
        Request::SocksAuthReply { reply } => socks5::auth_reply(&reply).map(|()| Response::Unit),
        Request::SocksRequest { command, target } => {
            socks5::request(command, &target).map(Response::Bytes)
        }
        Request::SocksUdpAssociate => Ok(Response::Bytes(socks5::udp_associate_request())),
        Request::SocksReply { frame } => socks5::parse_reply(&frame).map(Response::Reply),
        Request::SocksDatagram { target, payload } => {
            socks5::datagram(&target, &payload).map(Response::Bytes)
        }
        Request::SocksDatagramParse { datagram } => {
            socks5::parse_datagram(&datagram).map(|view| Response::Datagram {
                address: view.address,
                host_is_ip: view.host_is_ip,
                offset: view.offset,
            })
        }
        Request::HttpConnect {
            target,
            username,
            password,
        } => Ok(Response::Bytes(crate::http::connect_request(
            &target, &username, &password,
        ))),
    }
}

/// Encodes a response envelope.
pub fn encode_response(result: Result<Response, String>) -> Vec<u8> {
    let mut out = Vec::with_capacity(64);
    match result {
        Err(message) => {
            out.push(STATUS_ERROR);
            push_text(&mut out, &message);
        }
        Ok(response) => {
            out.push(STATUS_OK);
            match response {
                Response::Configured(config) => {
                    out.push(u8::from(config.enabled));
                    push_text(&mut out, &config.protocol);
                    push_text(&mut out, &config.host);
                    out.extend_from_slice(&config.port.to_le_bytes());
                    push_text(&mut out, &config.scope);
                    out.extend_from_slice(&(config.uids.len() as u32).to_le_bytes());
                    for uid in &config.uids {
                        out.extend_from_slice(&uid.to_le_bytes());
                    }
                }
                Response::Bytes(bytes) => push_bytes(&mut out, &bytes),
                Response::Method(code) => out.push(code),
                Response::Unit => {}
                Response::Reply(ReplyParse::Done { address }) => {
                    out.push(0);
                    push_text(&mut out, &address);
                }
                Response::Reply(ReplyParse::NeedMore(needed)) => {
                    out.push(1);
                    out.extend_from_slice(&(needed as u32).to_le_bytes());
                }
                Response::Datagram {
                    address,
                    host_is_ip,
                    offset,
                } => {
                    push_text(&mut out, &address);
                    out.push(u8::from(host_is_ip));
                    out.extend_from_slice(&(offset as u32).to_le_bytes());
                }
            }
        }
    }
    out
}

fn push_text(out: &mut Vec<u8>, text: &str) {
    push_bytes(out, text.as_bytes());
}

fn push_bytes(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(bytes);
}

struct Reader<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(payload: &'a [u8]) -> Self {
        Reader {
            payload,
            position: 0,
        }
    }

    fn at_end(&self) -> bool {
        self.position == self.payload.len()
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        let end = self.position.checked_add(length)?;
        if end > self.payload.len() {
            return None;
        }
        let slice = &self.payload[self.position..end];
        self.position = end;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|slice| slice[0])
    }

    fn i64(&mut self) -> Option<i64> {
        self.take(8)
            .map(|slice| i64::from_le_bytes(slice.try_into().unwrap()))
    }

    fn bytes(&mut self) -> Option<Vec<u8>> {
        let length = self.u32()? as usize;
        self.take(length).map(|slice| slice.to_vec())
    }

    fn text(&mut self) -> Option<String> {
        let bytes = self.bytes()?;
        String::from_utf8(bytes).ok()
    }

    fn u32(&mut self) -> Option<u32> {
        self.take(4)
            .map(|slice| u32::from_le_bytes(slice.try_into().unwrap()))
    }

    fn i64_list(&mut self) -> Option<Vec<i64>> {
        let count = self.u32()? as usize;
        let mut out = Vec::with_capacity(count.min(64));
        for _ in 0..count {
            out.push(self.i64()?);
        }
        Some(out)
    }
}

#[cfg(test)]
mod tests;

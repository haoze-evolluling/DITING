use crate::dns_config::{normalize, NormalizedConfig, Provider};
use crate::dynamic::DynamicBlock;
use crate::protocol::{parse_protocol, parse_response_type};
use crate::rewrite;

pub const LAYOUT_VERSION: u8 = 1;

pub const OP_DNS_CONFIG: u8 = 0;
pub const OP_PROTOCOL: u8 = 1;
pub const OP_RESPONSE_TYPE: u8 = 2;
pub const OP_DOMAIN: u8 = 4;
pub const OP_REWRITE: u8 = 5;

const STATUS_OK: u8 = 0;
const STATUS_ERROR: u8 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Request {
    DnsConfig {
        mode: String,
        block_response: String,
        enabled: bool,
        request_threshold: i64,
        window_seconds: i64,
        nxdomain_seconds: i64,
        providers: Vec<Provider>,
    },
    Protocol {
        text: String,
    },
    ResponseType {
        text: String,
    },
    Domain {
        domain: String,
    },
    Rewrite {
        targets: Vec<String>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    Ok(Vec<u8>),
    Error(String),
}

struct Reader<'a> {
    body: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(body: &'a [u8]) -> Self {
        Self { body, position: 0 }
    }

    fn at_end(&self) -> bool {
        self.position == self.body.len()
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        if length > self.body.len() - self.position {
            return None;
        }
        let slice = &self.body[self.position..self.position + length];
        self.position += length;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|slice| slice[0])
    }

    fn i64(&mut self) -> Option<i64> {
        let slice = self.take(8)?;
        Some(i64::from_le_bytes(slice.try_into().ok()?))
    }

    fn text(&mut self) -> Option<String> {
        let length = u32::from_le_bytes(self.take(4)?.try_into().ok()?) as usize;
        String::from_utf8(self.take(length)?.to_vec()).ok()
    }

    fn count(&mut self, stride: usize) -> Option<usize> {
        let count = self.i64()?;
        if count < 0 || (count as usize) > self.body.len() {
            return None;
        }
        let count = count as usize;
        if count.saturating_mul(stride) > self.body.len() - self.position {
            return None;
        }
        Some(count)
    }
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn put_i64(out: &mut Vec<u8>, value: i64) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn ok_text(text: &str) -> Response {
    let mut body = Vec::with_capacity(text.len() + 4);
    put_text(&mut body, text);
    Response::Ok(body)
}

fn ok_i64(value: i64) -> Response {
    let mut body = Vec::with_capacity(8);
    put_i64(&mut body, value);
    Response::Ok(body)
}

pub fn decode_request(payload: &[u8]) -> Option<Request> {
    let mut reader = Reader::new(payload);
    let op = reader.u8()?;
    let request = match op {
        OP_DNS_CONFIG => {
            let mode = reader.text()?;
            let block_response = reader.text()?;
            let enabled = match reader.i64()? {
                0 => false,
                1 => true,
                _ => return None,
            };
            let request_threshold = reader.i64()?;
            let window_seconds = reader.i64()?;
            let nxdomain_seconds = reader.i64()?;
            let count = reader.count(16)?;
            let mut providers = Vec::with_capacity(count);
            for _ in 0..count {
                providers.push(Provider {
                    id: reader.text()?,
                    protocol: reader.text()?,
                    server: reader.text()?,
                    url: reader.text()?,
                    weight: reader.i64()?,
                });
            }
            Request::DnsConfig {
                mode,
                block_response,
                enabled,
                request_threshold,
                window_seconds,
                nxdomain_seconds,
                providers,
            }
        }
        OP_PROTOCOL => Request::Protocol {
            text: reader.text()?,
        },
        OP_RESPONSE_TYPE => Request::ResponseType {
            text: reader.text()?,
        },
        OP_DOMAIN => Request::Domain {
            domain: reader.text()?,
        },
        OP_REWRITE => {
            let count = reader.count(4)?;
            let mut targets = Vec::with_capacity(count);
            for _ in 0..count {
                targets.push(reader.text()?);
            }
            Request::Rewrite { targets }
        }
        _ => return None,
    };
    if !reader.at_end() {
        return None;
    }
    Some(request)
}

pub fn handle(request: Request) -> Response {
    match request {
        Request::DnsConfig {
            mode,
            block_response,
            enabled,
            request_threshold,
            window_seconds,
            nxdomain_seconds,
            providers,
        } => {
            let dynamic = DynamicBlock::normalized(
                enabled,
                request_threshold,
                window_seconds,
                nxdomain_seconds,
            );
            match normalize(&mode, &block_response, dynamic, &providers) {
                Ok(config) => Response::Ok(encode_config(&config)),
                Err(message) => Response::Error(message),
            }
        }
        Request::Protocol { text } => ok_i64(parse_protocol(&text).code()),
        Request::ResponseType { text } => ok_i64(parse_response_type(&text).code()),
        Request::Domain { domain } => ok_text(&rewrite::normalize_domain(&domain)),
        Request::Rewrite { targets } => {
            let entry = rewrite::classify(&targets).unwrap_or_default();
            let mut body =
                Vec::with_capacity(entry.cname.len() + entry.ip4.len() + entry.ip6.len() + 12);
            put_text(&mut body, &entry.cname);
            put_text(&mut body, &entry.ip4);
            put_text(&mut body, &entry.ip6);
            Response::Ok(body)
        }
    }
}

fn encode_config(config: &NormalizedConfig) -> Vec<u8> {
    let mut body = Vec::new();
    put_text(&mut body, config.mode);
    put_i64(&mut body, config.block_response.code());
    put_i64(&mut body, i64::from(config.dynamic.enabled));
    put_i64(&mut body, config.dynamic.request_threshold);
    put_i64(&mut body, config.dynamic.window_seconds);
    put_i64(&mut body, config.dynamic.nxdomain_seconds);
    put_i64(&mut body, config.providers.len() as i64);
    for provider in &config.providers {
        put_text(&mut body, &provider.id);
        put_text(&mut body, provider.protocol.name());
        put_text(&mut body, &provider.server);
        put_text(&mut body, &provider.url);
        put_i64(&mut body, provider.weight);
    }
    body
}

pub fn encode_response(response: Response) -> Vec<u8> {
    match response {
        Response::Ok(body) => {
            let mut out = Vec::with_capacity(body.len() + 1);
            out.push(STATUS_OK);
            out.extend_from_slice(&body);
            out
        }
        Response::Error(message) => {
            let mut out = Vec::with_capacity(message.len() + 5);
            out.push(STATUS_ERROR);
            put_text(&mut out, &message);
            out
        }
    }
}

#[cfg(test)]
mod tests;

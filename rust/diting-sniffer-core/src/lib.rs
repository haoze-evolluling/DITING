pub mod ffi;
pub mod http;
pub mod payload;
pub mod tls;

pub use http::{go_trim_space_bytes, looks_like_http_request, parse_http_host};
pub use tls::parse_client_hello_sni;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Kind {
    Unknown = payload::KIND_UNKNOWN,
    Tls = payload::KIND_TLS,
    Http = payload::KIND_HTTP,
}

impl Kind {
    pub fn from_u8(value: u8) -> Option<Kind> {
        match value {
            payload::KIND_UNKNOWN => Some(Kind::Unknown),
            payload::KIND_TLS => Some(Kind::Tls),
            payload::KIND_HTTP => Some(Kind::Http),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Sniffed {
    pub kind: Kind,
    pub host: Vec<u8>,
}

pub fn classify(data: &[u8]) -> Sniffed {
    if data.len() >= 3 && data[0] == 0x16 && data[1] == 0x03 {
        return Sniffed {
            kind: Kind::Tls,
            host: parse_client_hello_sni(data).to_vec(),
        };
    }
    if looks_like_http_request(data) {
        return Sniffed {
            kind: Kind::Http,
            host: parse_http_host(data).to_vec(),
        };
    }
    Sniffed {
        kind: Kind::Unknown,
        host: Vec::new(),
    }
}

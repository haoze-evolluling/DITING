//! The flow sniffer behind the Android tunnel engine's MITM path.
//!
//! When a TCP flow to port 80 or 443 is accepted, the engine peeks at the first chunk the client
//! sends and has to decide, before any TLS handshake or HTTP parse of its own:
//!
//! * is this a TLS `ClientHello`, and if so what is the SNI hostname?
//! * is this a plaintext HTTP request, and if so what does its `Host` header say?
//! * neither — hand the replaying reader to the passthrough relay unchanged.
//!
//! [`classify`] is the whole decision. [`tls`] and [`http`] are the two parsers; both work on
//! `&[u8]` and never assume UTF-8, because the bytes come straight off a socket and the Go caller
//! treats hostnames as byte strings until it lowercases them for rule matching.
//!
//! What stays in Go: the single `Read` that fills the peek buffer (`peekFlow`), the replaying
//! reader, the timeout, and the dial/relay itself. The kernel only answers "what is this and what
//! host does it name".

pub mod ffi;
pub mod http;
pub mod payload;
pub mod tls;

pub use http::{go_trim_space_bytes, looks_like_http_request, parse_http_host};
pub use tls::parse_client_hello_sni;

/// What the peeked bytes look like.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Kind {
    /// Neither a TLS ClientHello nor a plaintext HTTP request.
    Unknown = payload::KIND_UNKNOWN,
    /// A TLS record the engine may intercept; [`Sniffed::host`] is the SNI (possibly empty).
    Tls = payload::KIND_TLS,
    /// A plaintext HTTP request; [`Sniffed::host`] is the `Host` header value (possibly empty).
    Http = payload::KIND_HTTP,
}

impl Kind {
    /// Decodes the payload byte, rejecting anything that is not one of the three kinds.
    pub fn from_u8(value: u8) -> Option<Kind> {
        match value {
            payload::KIND_UNKNOWN => Some(Kind::Unknown),
            payload::KIND_TLS => Some(Kind::Tls),
            payload::KIND_HTTP => Some(Kind::Http),
            _ => None,
        }
    }
}

/// One classification: the kind plus the hostname the parser extracted, if any.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Sniffed {
    /// What the bytes look like.
    pub kind: Kind,
    /// The SNI or `Host` value, raw bytes and not yet lowercased.
    pub host: Vec<u8>,
}

/// Classifies one peeked flow, exactly like the Go decision pipeline did.
///
/// The TLS gate is the one the relay used, not the parser's own: at least three bytes, a handshake
/// record (`0x16`) and a major version of `3`. A record that passes the gate but not the parser
/// still classifies as TLS with an empty host, so the caller falls back to the IP address instead
/// of relaying the flow as something else.
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

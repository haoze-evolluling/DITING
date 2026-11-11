//! `sdns://` DNS stamps, parsed byte for byte like `go-dnsstamps` and like the Go code this
//! replaced (`desktop/service/internal/core/resolver_stamp.go`):
//!
//! * the first byte is the protocol id, followed by an 8-byte little-endian props bitmap;
//! * string fields are lp-strings (1 length byte + body);
//! * certificate hashes and bootstrap IPs are VLP lists (high bit `0x80` means "one more item").
//!
//! DNSCrypt and ODoH stamps stay unsupported and are reported as errors, never silently
//! downgraded. The parsed value also carries the strings the Go caller used to derive itself
//! (`URL()` / `Server()`), so the defaults for ports and the DoH path live in exactly one place.

use std::net::{Ipv4Addr, Ipv6Addr};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;

/// Scheme every stamp starts with (`sdns:` is required, the `//` is optional on input).
pub const STAMP_SCHEME: &str = "sdns:";

/// Default port of the protocols whose stamps may omit it.
pub const DEFAULT_HTTPS_PORT: u16 = 443;
pub const DEFAULT_TLS_PORT: u16 = 853;
pub const DEFAULT_DNS_PORT: u16 = 53;

/// Length of a SHA-256(RawTBSCertificate) pin inside a stamp.
pub const HASH_LEN: usize = 32;

const PROTO_PLAIN: u8 = 0x00;
const PROTO_DOH: u8 = 0x02;
const PROTO_TLS: u8 = 0x03;
const PROTO_DOQ: u8 = 0x04;
const PROTO_DNSCRYPT: u8 = 0x01;
const PROTO_ODOH_TARGET: u8 = 0x05;
const PROTO_DNSCRYPT_RELAY: u8 = 0x81;
const PROTO_ODOH_RELAY: u8 = 0x85;

/// Stamp protocol id. Only the four protocols the resolver implements are representable.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Proto {
    Plain,
    DoH,
    Tls,
    DoQ,
}

impl Proto {
    /// On-wire protocol byte, the value the Go side stores in `ServerStamp.Proto`.
    pub fn code(self) -> u8 {
        match self {
            Proto::Plain => PROTO_PLAIN,
            Proto::DoH => PROTO_DOH,
            Proto::Tls => PROTO_TLS,
            Proto::DoQ => PROTO_DOQ,
        }
    }

    /// Display name, identical to `StampProtoType.String()`.
    pub fn name(self) -> &'static str {
        match self {
            Proto::Plain => "Plain",
            Proto::DoH => "DoH",
            Proto::Tls => "TLS",
            Proto::DoQ => "DoQ",
        }
    }

    /// Upstream protocol enum name, identical to the Go `DNSProtocol` constants.
    pub fn protocol(self) -> &'static str {
        match self {
            Proto::Plain => "PLAIN",
            Proto::DoH => "DOH",
            Proto::Tls => "DOT",
            Proto::DoQ => "DOQ",
        }
    }

    /// Port implied by the protocol when neither the stamp nor the address carries one.
    pub fn default_port(self) -> u16 {
        match self {
            Proto::Plain => DEFAULT_DNS_PORT,
            Proto::DoH => DEFAULT_HTTPS_PORT,
            Proto::Tls | Proto::DoQ => DEFAULT_TLS_PORT,
        }
    }
}

/// A parsed stamp. Field names follow the Go struct the caller still exposes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Stamp {
    pub proto: Proto,
    pub props: u64,
    /// Direct address, always `host:port`; empty for DoH stamps that rely on the hostname.
    pub server_addr: String,
    /// SHA-256 certificate pins.
    pub hashes: Vec<[u8; HASH_LEN]>,
    /// Hostname used for SNI and certificate validation (may carry a port).
    pub provider_name: String,
    /// DoH path as written in the stamp (may be empty).
    pub path: String,
    /// Bootstrap IPs carried by the stamp, unvalidated on purpose (as before).
    pub bootstrap_ips: Vec<String>,
}

impl Stamp {
    fn new(proto: Proto, props: u64, server_addr: String) -> Self {
        Stamp {
            proto,
            props,
            server_addr,
            hashes: Vec::new(),
            provider_name: String::new(),
            path: String::new(),
            bootstrap_ips: Vec::new(),
        }
    }

    /// Full DoH URL, empty for every other protocol. An empty path falls back to `/dns-query`.
    pub fn url(&self) -> String {
        if self.proto != Proto::DoH {
            return String::new();
        }
        let path = if self.path.is_empty() {
            "/dns-query".to_string()
        } else if self.path.starts_with('/') {
            self.path.clone()
        } else {
            format!("/{}", self.path)
        };
        format!(
            "https://{}{}",
            self.host_with_port(DEFAULT_HTTPS_PORT),
            path
        )
    }

    /// Address to put into `ProviderConfig.Server`: the protocol default port is omitted.
    pub fn server(&self) -> String {
        if self.provider_name.is_empty() {
            return self.server_addr.clone();
        }
        self.host_with_port(self.proto.default_port())
    }

    /// Hostname with port; the port equals the protocol default is dropped.
    ///
    /// Port precedence: port inside the stamp hostname > port of the direct address > default.
    fn host_with_port(&self, default_port: u16) -> String {
        let (host, mut port) = split_port(&self.provider_name);
        if port.is_empty() {
            port = split_port(&self.server_addr).1;
        }
        let host = host.trim_matches(|c| c == '[' || c == ']');
        if port.is_empty() || port == default_port.to_string() {
            return host.to_string();
        }
        join_host_port(host, port)
    }
}

/// Parses a stamp string. Errors are user-facing text and keep the wording of the Go original.
pub fn parse(stamp_text: &str) -> Result<Stamp, String> {
    let text = stamp_text.trim();
    if text.is_empty() {
        return Err("empty stamp".to_string());
    }
    let Some(rest) = text.strip_prefix(STAMP_SCHEME) else {
        return Err("stamps are expected to start with \"sdns:\"".to_string());
    };
    let encoded = rest.strip_prefix("//").unwrap_or(rest);
    let bin = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|err| format!("decode stamp base64: {err}"))?;
    if bin.is_empty() {
        return Err("stamp is too short".to_string());
    }

    match bin[0] {
        PROTO_PLAIN => parse_plain(&bin),
        PROTO_DOH => parse_doh(&bin),
        PROTO_TLS => parse_dot(&bin),
        PROTO_DOQ => parse_doq(&bin),
        PROTO_DNSCRYPT | PROTO_DNSCRYPT_RELAY => {
            Err("DNSCrypt 印章暂不支持，请改用 DoH / DoT / DoQ 印章".to_string())
        }
        PROTO_ODOH_TARGET | PROTO_ODOH_RELAY => {
            Err("oDoH 印章暂不支持，请改用 DoH / DoT / DoQ 印章".to_string())
        }
        other => Err(format!("unsupported stamp protocol byte 0x{other:02x}")),
    }
}

fn parse_plain(bin: &[u8]) -> Result<Stamp, String> {
    let mut reader = Reader::new(bin, 1);
    let props = reader.read_props()?;
    let addr = reader.read_lp_string(false)?;
    reader.expect_end()?;
    let addr = normalize_addr(&addr, DEFAULT_DNS_PORT)?;
    Ok(Stamp::new(Proto::Plain, props, addr))
}

fn parse_doh(bin: &[u8]) -> Result<Stamp, String> {
    let mut reader = Reader::new(bin, 1);
    let props = reader.read_props()?;
    // The direct address of a DoH stamp may be empty: the hostname is resolved normally then.
    let addr = reader.read_lp_string(true)?;
    let hashes = reader.read_hashes()?;
    let provider = reader.read_lp_string(false)?;
    let path = reader.read_lp_string(true)?;
    let bootstrap_ips = reader.read_optional_bootstrap_ips()?;
    reader.expect_end()?;

    let addr = if addr.is_empty() {
        addr
    } else {
        normalize_addr(&addr, DEFAULT_HTTPS_PORT)?
    };
    validate_hostname(&provider)?;

    let mut stamp = Stamp::new(Proto::DoH, props, addr);
    stamp.hashes = hashes;
    stamp.provider_name = provider;
    stamp.path = path;
    stamp.bootstrap_ips = bootstrap_ips;
    Ok(stamp)
}

fn parse_dot(bin: &[u8]) -> Result<Stamp, String> {
    let mut reader = Reader::new(bin, 1);
    let props = reader.read_props()?;
    let addr = reader.read_lp_string(true)?;
    let hashes = reader.read_hashes()?;
    let provider = reader.read_lp_string(false)?;
    let bootstrap_ips = reader.read_optional_bootstrap_ips()?;
    reader.expect_end()?;

    let addr = if addr.is_empty() {
        addr
    } else {
        normalize_addr(&addr, DEFAULT_TLS_PORT)?
    };
    validate_hostname(&provider)?;

    let mut stamp = Stamp::new(Proto::Tls, props, addr);
    stamp.hashes = hashes;
    stamp.provider_name = provider;
    stamp.bootstrap_ips = bootstrap_ips;
    Ok(stamp)
}

fn parse_doq(bin: &[u8]) -> Result<Stamp, String> {
    // DoQ shares the DoT layout byte for byte; only the protocol id differs.
    let mut stamp = parse_dot(bin)?;
    stamp.proto = Proto::DoQ;
    Ok(stamp)
}

/// Bounds-checked sequential reader, so no index arithmetic is written by hand.
struct Reader<'a> {
    bin: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(bin: &'a [u8], pos: usize) -> Self {
        Reader { bin, pos }
    }

    fn remaining(&self) -> usize {
        self.bin.len() - self.pos
    }

    /// 8-byte little-endian props bitmap.
    fn read_props(&mut self) -> Result<u64, String> {
        if self.remaining() < 8 {
            return Err("stamp is too short (props)".to_string());
        }
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&self.bin[self.pos..self.pos + 8]);
        self.pos += 8;
        Ok(u64::from_le_bytes(bytes))
    }

    /// lp-string: one length byte plus the body.
    fn read_lp_string(&mut self, allow_empty: bool) -> Result<String, String> {
        if self.remaining() < 1 {
            return Err("stamp is too short (length byte)".to_string());
        }
        let length = self.bin[self.pos] as usize;
        self.pos += 1;
        if self.remaining() < length {
            return Err("stamp is truncated (string body)".to_string());
        }
        if length == 0 && !allow_empty {
            return Err("stamp contains an unexpected empty string".to_string());
        }
        self.read_text(length)
    }

    fn read_text(&mut self, length: usize) -> Result<String, String> {
        let body = &self.bin[self.pos..self.pos + length];
        self.pos += length;
        std::str::from_utf8(body)
            .map(str::to_string)
            .map_err(|_| "stamp contains a string field that is not valid UTF-8".to_string())
    }

    /// VLP list of strings; `elem_len` > 0 pins the element size.
    fn read_vlp_strings(&mut self, elem_len: usize) -> Result<Vec<String>, String> {
        let mut out = Vec::new();
        loop {
            if self.remaining() < 1 {
                return Err("stamp is truncated (VLP length byte)".to_string());
            }
            let vlen = self.bin[self.pos] as usize;
            let length = vlen & !0x80;
            self.pos += 1;
            if self.remaining() < length {
                return Err("stamp is truncated (VLP body)".to_string());
            }
            if length > 0 {
                if elem_len > 0 && length != elem_len {
                    return Err(format!(
                        "stamp has an invalid {length}-byte element (want {elem_len})"
                    ));
                }
                out.push(self.read_text(length)?);
            }
            if vlen & 0x80 != 0x80 {
                break;
            }
        }
        Ok(out)
    }

    /// Certificate pins: VLP with a fixed 32-byte element size.
    fn read_hashes(&mut self) -> Result<Vec<[u8; HASH_LEN]>, String> {
        let mut out = Vec::new();
        loop {
            if self.remaining() < 1 {
                return Err("stamp is truncated (hash length byte)".to_string());
            }
            let vlen = self.bin[self.pos] as usize;
            let length = vlen & !0x80;
            self.pos += 1;
            if self.remaining() < length {
                return Err("stamp is truncated (hash body)".to_string());
            }
            if length > 0 {
                if length != HASH_LEN {
                    return Err(format!(
                        "stamp certificate hash must be {HASH_LEN} bytes, got {length}"
                    ));
                }
                let mut hash = [0u8; HASH_LEN];
                hash.copy_from_slice(&self.bin[self.pos..self.pos + length]);
                out.push(hash);
            }
            self.pos += length;
            if vlen & 0x80 != 0x80 {
                break;
            }
        }
        Ok(out)
    }

    /// Optional trailing bootstrap-IP section; absent means "no bytes left".
    fn read_optional_bootstrap_ips(&mut self) -> Result<Vec<String>, String> {
        if self.remaining() == 0 {
            return Ok(Vec::new());
        }
        self.read_vlp_strings(0)
    }

    fn expect_end(&self) -> Result<(), String> {
        if self.remaining() != 0 {
            return Err("stamp has garbage after end".to_string());
        }
        Ok(())
    }
}

/// Validates a direct address and fills in the protocol default port.
fn normalize_addr(addr: &str, default_port: u16) -> Result<String, String> {
    let (host, port) = split_port(addr);
    let port = if port.is_empty() {
        if addr.ends_with(':') {
            return Err("stamp has an empty port".to_string());
        }
        default_port.to_string()
    } else {
        validate_port(port)?;
        port.to_string()
    };

    let ip_only = host.strip_prefix('[').unwrap_or(host);
    let ip_only = ip_only.strip_suffix(']').unwrap_or(ip_only);
    if !is_ip_literal(ip_only) {
        return Err(format!(
            "stamp server address {host:?} is not an IP address"
        ));
    }
    Ok(join_host_port(ip_only, &port))
}

/// Validates the stamp hostname, which may carry a port.
fn validate_hostname(hostname: &str) -> Result<(), String> {
    if hostname.is_empty() {
        return Err("stamp has an empty hostname".to_string());
    }
    let (host, port) = split_port(hostname);
    if !port.is_empty() {
        validate_port(port)?;
    } else if hostname.ends_with(':') {
        return Err("stamp has an empty port".to_string());
    }
    if host.trim().is_empty() {
        return Err("stamp has an empty hostname".to_string());
    }
    Ok(())
}

fn validate_port(port: &str) -> Result<(), String> {
    let digits = !port.is_empty() && port.bytes().all(|byte| byte.is_ascii_digit());
    let parsed = digits.then(|| port.parse::<u16>());
    match parsed {
        Some(Ok(value)) if value != 0 => Ok(()),
        _ => Err(format!("stamp has an invalid port {port:?}")),
    }
}

fn is_ip_literal(value: &str) -> bool {
    value.parse::<Ipv4Addr>().is_ok() || value.parse::<Ipv6Addr>().is_ok()
}

/// Splits at the last colon, keeping IPv6 literals intact; no port yields an empty port.
///
/// The Go side keeps an identical helper (`splitStampPort`) because the pin lookup table uses it
/// for plain `host:port` server strings too.
fn split_port(value: &str) -> (&str, &str) {
    let Some(colon) = value.rfind(':') else {
        return (value, "");
    };
    if let Some(bracket) = value.rfind(']') {
        // `[::1]` without a port: the colon belongs to the literal, not to a port.
        if colon < bracket {
            return (value, "");
        }
    }
    (&value[..colon], &value[colon + 1..])
}

/// `net.JoinHostPort` semantics: brackets only for hosts that contain a colon.
fn join_host_port(host: &str, port: &str) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

#[cfg(test)]
mod tests;

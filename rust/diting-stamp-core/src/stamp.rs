use std::net::{Ipv4Addr, Ipv6Addr};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;

pub const STAMP_SCHEME: &str = "sdns:";

pub const DEFAULT_HTTPS_PORT: u16 = 443;
pub const DEFAULT_TLS_PORT: u16 = 853;
pub const DEFAULT_DNS_PORT: u16 = 53;

pub const HASH_LEN: usize = 32;

const PROTO_PLAIN: u8 = 0x00;
const PROTO_DOH: u8 = 0x02;
const PROTO_TLS: u8 = 0x03;
const PROTO_DOQ: u8 = 0x04;
const PROTO_DNSCRYPT: u8 = 0x01;
const PROTO_ODOH_TARGET: u8 = 0x05;
const PROTO_DNSCRYPT_RELAY: u8 = 0x81;
const PROTO_ODOH_RELAY: u8 = 0x85;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Proto {
    Plain,
    DoH,
    Tls,
    DoQ,
}

impl Proto {
    pub fn code(self) -> u8 {
        match self {
            Proto::Plain => PROTO_PLAIN,
            Proto::DoH => PROTO_DOH,
            Proto::Tls => PROTO_TLS,
            Proto::DoQ => PROTO_DOQ,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Proto::Plain => "Plain",
            Proto::DoH => "DoH",
            Proto::Tls => "TLS",
            Proto::DoQ => "DoQ",
        }
    }

    pub fn protocol(self) -> &'static str {
        match self {
            Proto::Plain => "PLAIN",
            Proto::DoH => "DOH",
            Proto::Tls => "DOT",
            Proto::DoQ => "DOQ",
        }
    }

    pub fn default_port(self) -> u16 {
        match self {
            Proto::Plain => DEFAULT_DNS_PORT,
            Proto::DoH => DEFAULT_HTTPS_PORT,
            Proto::Tls | Proto::DoQ => DEFAULT_TLS_PORT,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Stamp {
    pub proto: Proto,
    pub props: u64,
    pub server_addr: String,
    pub hashes: Vec<[u8; HASH_LEN]>,
    pub provider_name: String,
    pub path: String,
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

    pub fn server(&self) -> String {
        if self.provider_name.is_empty() {
            return self.server_addr.clone();
        }
        self.host_with_port(self.proto.default_port())
    }

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
    let mut stamp = parse_dot(bin)?;
    stamp.proto = Proto::DoQ;
    Ok(stamp)
}

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

    fn read_props(&mut self) -> Result<u64, String> {
        if self.remaining() < 8 {
            return Err("stamp is too short (props)".to_string());
        }
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&self.bin[self.pos..self.pos + 8]);
        self.pos += 8;
        Ok(u64::from_le_bytes(bytes))
    }

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

fn split_port(value: &str) -> (&str, &str) {
    let Some(colon) = value.rfind(':') else {
        return (value, "");
    };
    if let Some(bracket) = value.rfind(']') {
        if colon < bracket {
            return (value, "");
        }
    }
    (&value[..colon], &value[colon + 1..])
}

fn join_host_port(host: &str, port: &str) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}

#[cfg(test)]
mod tests;

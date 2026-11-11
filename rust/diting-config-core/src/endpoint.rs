//! Upstream endpoint validation: `validateDNSProvider` and `parseDoQURL`.
//!
//! Three endpoint forms reach this module and each has its own rule set:
//!
//! * `PLAIN` / `DOT` take `host:port`. `net.SplitHostPort` decides the split, and the host must then
//!   be either empty-free and colon-free, or a real IPv6 literal (`[1.1.1.1:53]:53` splits to the
//!   *host* `1.1.1.1:53`, which cannot be dialed). Hostnames are fine — only the shape is checked.
//! * `DOH` takes a URL that `url.ParseRequestURI` accepts, with an `https` scheme and a non-empty
//!   host. `https://dns.google:443/x`, `HTTPS://…`, userinfo, an empty port and a `#fragment` all
//!   pass, while a non-digit port, a space in the host, a bad percent escape and control bytes do
//!   not.
//! * `DOQ` takes the loose form `parseDoQURL` parses: any of the `quic://` / `https://` / `doq://`
//!   prefixes, an optional path, then `host:port` with the port defaulting to 853.

use diting_go_compat::netaddr::{parse_ip, split_host_port};

use crate::protocol::{validated_protocol, Protocol};
use crate::quote::go_quote;

/// `validateDNSProvider`: validates one provider and returns its protocol.
///
/// `protocol` is the raw config value; the strict table upper-cases it first, so the error text
/// carries the upper-cased spelling.
pub fn validate_provider(protocol: &str, server: &str, url: &str) -> Result<Protocol, String> {
    let protocol = validated_protocol(protocol)?;
    match protocol {
        Protocol::Plain | Protocol::Dot => validate_host_port(protocol, server)?,
        Protocol::Doh => validate_doh(url)?,
        Protocol::Doq => validate_doq(url)?,
    }
    Ok(protocol)
}

/// The `PLAIN` / `DOT` branch: `net.SplitHostPort`, then the IPv6-literal rule.
fn validate_host_port(protocol: Protocol, server: &str) -> Result<(), String> {
    let name = protocol.name();
    let host = match split_host_port(server) {
        Ok((host, _port)) => host,
        Err(err) => {
            return Err(format!(
                "invalid {name} endpoint {}: {err}",
                go_quote(server)
            ))
        }
    };
    // Only a real IPv6 literal may still contain a colon after the split: anything else means the
    // address itself had a port appended (`[1.1.1.1:53]:53`) and cannot dial.
    if host.is_empty() || (host.contains(':') && parse_ip(host).is_none()) {
        return Err(format!(
            "invalid {name} endpoint {}: host is not a valid IP literal",
            go_quote(server)
        ));
    }
    Ok(())
}

fn validate_doh(url: &str) -> Result<(), String> {
    match parse_request_uri(url) {
        Some(uri) if uri.scheme == "https" && !uri.host.is_empty() => Ok(()),
        _ => Err(format!("invalid DOH URL {}", go_quote(url))),
    }
}

fn validate_doq(url: &str) -> Result<(), String> {
    let (host, port) = parse_doq_url(url);
    if host.is_empty() || port.is_empty() {
        return Err(format!("invalid DOQ URL {}", go_quote(url)));
    }
    Ok(())
}

/// `parseDoQURL`: strip one of the three prefixes, drop the path, then `host:port` (853 if the split
/// fails, which is what the old helper returned for a bare host).
pub fn parse_doq_url(url: &str) -> (String, String) {
    let mut rest = url;
    for prefix in ["quic://", "https://", "doq://"] {
        if let Some(stripped) = rest.strip_prefix(prefix) {
            rest = stripped;
        }
    }
    if let Some(index) = rest.find('/') {
        rest = &rest[..index];
    }
    match split_host_port(rest) {
        Ok((host, port)) => (host.to_string(), port.to_string()),
        Err(_) => (rest.to_string(), DEFAULT_DOQ_PORT.to_string()),
    }
}

/// The port `parseDoQURL` falls back to.
pub const DEFAULT_DOQ_PORT: &str = "853";

/// What [`parse_request_uri`] keeps: the lower-cased scheme and the authority's host (with port).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestUri {
    pub scheme: String,
    pub host: String,
}

/// `url.ParseRequestURI`, reduced to what the DoH check reads.
///
/// Returns `None` where Go returns an error. The error *texts* are not reproduced because the caller
/// replaces them with `invalid DOH URL %q` anyway; the accept/reject set is what matters and is
/// pinned by the corpus.
pub fn parse_request_uri(text: &str) -> Option<RequestUri> {
    if text.bytes().any(|byte| byte < 0x20 || byte == 0x7f) {
        return None; // "invalid control character in URL"
    }
    let (scheme, rest) = split_scheme(text)?;
    let Some(authority_and_path) = rest.strip_prefix("//") else {
        // `https:opaque` parses but has no host; `dns.google` has no scheme at all.
        return Some(RequestUri {
            scheme,
            host: String::new(),
        });
    };
    let end = authority_and_path
        .find(['/', '?', '#'])
        .unwrap_or(authority_and_path.len());
    let authority = &authority_and_path[..end];
    let authority = match authority.rfind('@') {
        Some(index) => &authority[index + 1..],
        None => authority,
    };
    if authority.contains('%') || authority.contains(' ') || authority.contains('\\') {
        return None; // `invalid URL escape` / `invalid character in host name`
    }
    if !valid_authority_port(authority) {
        return None; // `invalid port ":abc" after host`
    }
    Some(RequestUri {
        scheme,
        host: authority.to_string(),
    })
}

/// `getScheme`: `[A-Za-z][A-Za-z0-9+.-]*` before the first colon, lower-cased.
fn split_scheme(text: &str) -> Option<(String, &str)> {
    let index = text.find(':')?;
    let scheme = &text[..index];
    let mut bytes = scheme.bytes();
    let first = bytes.next()?;
    if !first.is_ascii_alphabetic() {
        return None;
    }
    if !bytes.all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'-' | b'.')) {
        return None;
    }
    Some((scheme.to_ascii_lowercase(), &text[index + 1..]))
}

/// The port, when the authority carries one, must be digits only (an empty port is allowed).
/// A bracketed IPv6 host is split at its closing bracket.
fn valid_authority_port(authority: &str) -> bool {
    let port = if let Some(rest) = authority.strip_prefix('[') {
        let Some(close) = rest.find(']') else {
            return false;
        };
        match &rest[close + 1..] {
            "" => return true,
            after => match after.strip_prefix(':') {
                Some(port) => port,
                None => return false,
            },
        }
    } else {
        match authority.rfind(':') {
            Some(index) => &authority[index + 1..],
            None => return true,
        }
    };
    port.bytes().all(|byte| byte.is_ascii_digit())
}

#[cfg(test)]
mod tests;

use diting_go_compat::netaddr::{parse_ip, split_host_port};

use crate::protocol::{validated_protocol, Protocol};
use crate::quote::go_quote;

pub fn validate_provider(protocol: &str, server: &str, url: &str) -> Result<Protocol, String> {
    let protocol = validated_protocol(protocol)?;
    match protocol {
        Protocol::Plain | Protocol::Dot => validate_host_port(protocol, server)?,
        Protocol::Doh => validate_doh(url)?,
    }
    Ok(protocol)
}

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestUri {
    pub scheme: String,
    pub host: String,
}

pub fn parse_request_uri(text: &str) -> Option<RequestUri> {
    if text.bytes().any(|byte| byte < 0x20 || byte == 0x7f) {
        return None;
    }
    let (scheme, rest) = split_scheme(text)?;
    let Some(authority_and_path) = rest.strip_prefix("//") else {
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
        return None;
    }
    if !valid_authority_port(authority) {
        return None;
    }
    Some(RequestUri {
        scheme,
        host: authority.to_string(),
    })
}

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

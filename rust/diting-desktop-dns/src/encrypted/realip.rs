use std::net::{IpAddr, SocketAddr};

use hyper::HeaderMap;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ReverseProxyConfig {
    pub enabled: bool,
    pub trusted_sources: Vec<String>,
    pub client_ip_header: String,
}

const X_FORWARDED_FOR: &str = "x-forwarded-for";
const X_REAL_IP: &str = "x-real-ip";

pub fn real_client_ip(
    peer: IpAddr,
    headers: &HeaderMap,
    trusted: &[String],
    header: &str,
) -> IpAddr {
    let peer = canonical(peer);
    if trusted.is_empty() || !is_trusted(peer, trusted) {
        return peer;
    }

    let custom = header.trim();
    if !custom.is_empty() {
        let value = headers.get(custom).and_then(|value| value.to_str().ok());
        let resolved = if custom.eq_ignore_ascii_case(X_FORWARDED_FOR) {
            value.and_then(|value| forwarded_for(value, trusted))
        } else {
            value.and_then(parse_header_ip)
        };
        if let Some(ip) = resolved {
            return ip;
        }
    }

    if let Some(value) = headers
        .get(X_FORWARDED_FOR)
        .and_then(|value| value.to_str().ok())
    {
        if let Some(ip) = forwarded_for(value, trusted) {
            return ip;
        }
    }
    if let Some(value) = headers.get(X_REAL_IP).and_then(|value| value.to_str().ok()) {
        if let Some(ip) = parse_header_ip(value) {
            return ip;
        }
    }
    peer
}

fn forwarded_for(value: &str, trusted: &[String]) -> Option<IpAddr> {
    if value.trim().is_empty() {
        return None;
    }
    for part in value.split(',').rev() {
        let ip = parse_header_ip(part)?;
        if !is_trusted(ip, trusted) {
            return Some(ip);
        }
    }
    None
}

fn parse_header_ip(value: &str) -> Option<IpAddr> {
    let trimmed = value.trim().trim_matches('"');
    if trimmed.is_empty() {
        return None;
    }
    if let Ok(ip) = trimmed.parse::<IpAddr>() {
        return Some(canonical(ip));
    }
    trimmed
        .parse::<SocketAddr>()
        .ok()
        .map(|socket| canonical(socket.ip()))
}

fn canonical(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => IpAddr::V6(v6),
        },
        IpAddr::V4(_) => ip,
    }
}

fn is_trusted(ip: IpAddr, trusted: &[String]) -> bool {
    trusted
        .iter()
        .filter_map(|entry| parse_trusted(entry))
        .any(|entry| entry.contains(ip))
}

enum Trusted {
    Address(IpAddr),
    Network(IpAddr, u8),
}

impl Trusted {
    fn contains(&self, ip: IpAddr) -> bool {
        match self {
            Trusted::Address(address) => *address == ip,
            Trusted::Network(base, prefix) => same_prefix(base, *prefix, &ip),
        }
    }
}

fn parse_trusted(entry: &str) -> Option<Trusted> {
    let entry = entry.trim();
    if entry.is_empty() {
        return None;
    }
    if let Some((address, prefix)) = entry.split_once('/') {
        let base = canonical(address.trim().parse::<IpAddr>().ok()?);
        let prefix = prefix.trim().parse::<u8>().ok()?;
        if prefix > max_prefix(&base) {
            return None;
        }
        return Some(Trusted::Network(mask(base, prefix), prefix));
    }
    let ip = canonical(entry.parse::<IpAddr>().ok()?);
    Some(Trusted::Address(ip))
}

fn max_prefix(ip: &IpAddr) -> u8 {
    match ip {
        IpAddr::V4(_) => 32,
        IpAddr::V6(_) => 128,
    }
}

fn mask(ip: IpAddr, prefix: u8) -> IpAddr {
    match ip {
        IpAddr::V4(v4) => {
            let bits = u32::from(v4);
            let mask = if prefix == 0 {
                0
            } else {
                u32::MAX << (32 - prefix)
            };
            IpAddr::V4((bits & mask).into())
        }
        IpAddr::V6(v6) => {
            let bits = u128::from(v6);
            let mask = if prefix == 0 {
                0
            } else {
                u128::MAX << (128 - prefix)
            };
            IpAddr::V6((bits & mask).into())
        }
    }
}

fn same_prefix(base: &IpAddr, prefix: u8, ip: &IpAddr) -> bool {
    match (base, ip) {
        (IpAddr::V4(base), IpAddr::V4(ip)) => {
            let mask = if prefix == 0 {
                0
            } else {
                u32::MAX << (32 - prefix)
            };
            (u32::from(*base) & mask) == (u32::from(*ip) & mask)
        }
        (IpAddr::V6(base), IpAddr::V6(ip)) => {
            let mask = if prefix == 0 {
                0
            } else {
                u128::MAX << (128 - prefix)
            };
            (u128::from(*base) & mask) == (u128::from(*ip) & mask)
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hyper::header::HeaderValue;

    fn ip(text: &str) -> IpAddr {
        text.parse().unwrap()
    }

    fn headers(pairs: &[(&'static str, &str)]) -> HeaderMap {
        let mut map = HeaderMap::new();
        for (name, value) in pairs {
            map.append(*name, HeaderValue::from_str(value).unwrap());
        }
        map
    }

    #[test]
    fn untrusted_peer_ignores_forwarding_headers() {
        let map = headers(&[("x-forwarded-for", "8.8.8.8")]);
        let peer = ip("192.168.1.5");
        assert_eq!(real_client_ip(peer, &map, &["10.0.0.1".into()], ""), peer);
    }

    #[test]
    fn trusted_peer_honours_the_chain_from_the_right() {
        let trusted = vec!["10.0.0.0/8".to_string(), "127.0.0.1".to_string()];
        let map = headers(&[("x-forwarded-for", "9.9.9.9, 8.8.8.8, 10.1.2.3")]);
        assert_eq!(
            real_client_ip(ip("10.0.0.5"), &map, &trusted, ""),
            ip("8.8.8.8")
        );
    }

    #[test]
    fn custom_header_wins_over_the_standard_headers() {
        let trusted = vec!["127.0.0.1".to_string()];
        let map = headers(&[
            ("cf-connecting-ip", "1.1.1.1"),
            ("x-forwarded-for", "8.8.8.8"),
        ]);
        assert_eq!(
            real_client_ip(ip("127.0.0.1"), &map, &trusted, "CF-Connecting-IP"),
            ip("1.1.1.1")
        );
        let map = headers(&[("cf-connecting-ip", "9.9.9.9, 2.2.2.2")]);
        assert_eq!(
            real_client_ip(ip("127.0.0.1"), &map, &trusted, "cf-connecting-ip"),
            ip("127.0.0.1")
        );
    }

    #[test]
    fn malformed_chain_falls_back_to_the_peer() {
        let trusted = vec!["127.0.0.1".to_string()];
        let map = headers(&[("x-forwarded-for", "8.8.8.8, 10.0.0.1, garbage")]);
        assert_eq!(
            real_client_ip(ip("127.0.0.1"), &map, &trusted, ""),
            ip("127.0.0.1")
        );
    }

    #[test]
    fn x_real_ip_and_ports_and_brackets_are_understood() {
        let trusted = vec!["::1".to_string()];
        let map = headers(&[("x-real-ip", "[::ffff:1.2.3.4]:443")]);
        assert_eq!(real_client_ip(ip("::1"), &map, &trusted, ""), ip("1.2.3.4"));
    }

    #[test]
    fn cidr_prefixes_match_only_their_family() {
        assert!(is_trusted(ip("192.168.5.4"), &["192.168.0.0/16".into()]));
        assert!(!is_trusted(ip("192.169.5.4"), &["192.168.0.0/16".into()]));
        assert!(is_trusted(ip("2001:db8::1"), &["2001:db8::/32".into()]));
        assert!(!is_trusted(ip("2001:db9::1"), &["2001:db8::/32".into()]));
    }
}

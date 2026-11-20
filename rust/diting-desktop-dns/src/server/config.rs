use std::net::{IpAddr, SocketAddr};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerConfig {
    pub udp_addresses: Vec<String>,
    pub tcp_addresses: Vec<String>,
    pub read_timeout: Duration,
    pub write_timeout: Duration,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            udp_addresses: vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()],
            tcp_addresses: vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()],
            read_timeout: Duration::from_secs(5),
            write_timeout: Duration::from_secs(5),
        }
    }
}

impl ServerConfig {
    pub fn normalized(mut self) -> Self {
        if self.udp_addresses.is_empty() && self.tcp_addresses.is_empty() {
            return Self::default();
        }
        self.udp_addresses = deduplicate_addresses(&self.udp_addresses);
        self.tcp_addresses = deduplicate_addresses(&self.tcp_addresses);
        if self.read_timeout.is_zero() {
            self.read_timeout = Duration::from_secs(5);
        }
        if self.write_timeout.is_zero() {
            self.write_timeout = Duration::from_secs(5);
        }
        self
    }

    pub fn query_timeout(&self) -> Duration {
        let total = self.read_timeout + self.write_timeout;
        if total.is_zero() {
            Duration::from_secs(5)
        } else {
            total
        }
    }
}

pub fn deduplicate_addresses(addresses: &[String]) -> Vec<String> {
    let mut wildcard_v4 = Vec::new();
    let mut wildcard_v6 = Vec::new();
    for address in addresses {
        if let Ok(parsed) = parse_address(address) {
            if parsed.ip().is_unspecified() {
                if parsed.is_ipv4() {
                    wildcard_v4.push(parsed.port());
                } else {
                    wildcard_v6.push(parsed.port());
                }
            }
        }
    }
    let mut result = Vec::with_capacity(addresses.len());
    for address in addresses {
        if result.iter().any(|existing| existing == address) {
            continue;
        }
        if let Ok(parsed) = parse_address(address) {
            if !parsed.ip().is_unspecified() {
                let wildcard = if parsed.is_ipv4() {
                    &wildcard_v4
                } else {
                    &wildcard_v6
                };
                if wildcard.contains(&parsed.port()) {
                    continue;
                }
            }
        }
        result.push(address.clone());
    }
    result
}

pub fn parse_address(address: &str) -> Result<SocketAddr, String> {
    address
        .parse::<SocketAddr>()
        .map_err(|error| format!("无效的监听地址 {address}: {error}"))
}

pub fn is_ipv6(address: &str) -> bool {
    match parse_address(address) {
        Ok(parsed) => parsed.is_ipv6(),
        Err(_) => {
            let host = address.trim_start_matches('[');
            host.split(']').next().unwrap_or(host).contains(':')
                || address.starts_with("[::]")
                || matches!(address.parse::<IpAddr>(), Ok(ip) if ip.is_ipv6())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wildcard_swallows_specific_addresses() {
        let addresses = vec![
            "0.0.0.0:53".to_string(),
            "127.0.0.1:53".to_string(),
            "192.168.1.1:53".to_string(),
            "[::]:5353".to_string(),
            "[::1]:5353".to_string(),
            "127.0.0.1:5353".to_string(),
        ];
        assert_eq!(
            deduplicate_addresses(&addresses),
            vec![
                "0.0.0.0:53".to_string(),
                "[::]:5353".to_string(),
                "127.0.0.1:5353".to_string()
            ]
        );
    }

    #[test]
    fn defaults_are_dual_stack_loopback() {
        let config = ServerConfig {
            udp_addresses: Vec::new(),
            tcp_addresses: Vec::new(),
            ..ServerConfig::default()
        }
        .normalized();
        assert_eq!(config.udp_addresses.len(), 2);
        assert!(is_ipv6("[::1]:53"));
        assert!(!is_ipv6("127.0.0.1:53"));
    }
}

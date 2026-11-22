use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, RwLock};

pub const SYSTEM_DNS_PORT: u16 = 53;
pub const DEGRADED_WINDOW_NS: i64 = 5_000_000_000;

/// 当前物理网络下发的 DNS。仅在配置的上游全部失败后作为兜底使用，
/// 避免把每一次查询都泄露给运营商解析器。
#[derive(Clone, Default)]
pub struct SystemDns {
    servers: Arc<RwLock<Vec<SocketAddr>>>,
    degraded_until_ns: Arc<AtomicI64>,
}

impl SystemDns {
    pub fn set(&self, raw: &str) {
        let servers = parse_servers(raw);
        *self
            .servers
            .write()
            .unwrap_or_else(|error| error.into_inner()) = servers;
    }

    pub fn servers(&self) -> Vec<SocketAddr> {
        self.servers
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn is_empty(&self) -> bool {
        self.servers
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .is_empty()
    }

    /// 最近一轮上游全部失败后，后续查询优先走系统 DNS，避免每次都等满上游超时。
    pub fn is_degraded(&self, now_ns: i64) -> bool {
        !self.is_empty() && now_ns < self.degraded_until_ns.load(Ordering::Acquire)
    }

    pub fn mark_degraded(&self, now_ns: i64) {
        self.degraded_until_ns
            .store(now_ns.saturating_add(DEGRADED_WINDOW_NS), Ordering::Release);
    }

    pub fn clear_degraded(&self) {
        self.degraded_until_ns.store(0, Ordering::Release);
    }
}

fn parse_servers(raw: &str) -> Vec<SocketAddr> {
    let mut servers = Vec::new();
    for token in raw.split(['\n', '\r', ',', ';', ' ', '\t']) {
        let token = token.trim();
        if token.is_empty() {
            continue;
        }
        if let Some(address) = parse_server(token) {
            if address.port() != 0 && !servers.contains(&address) {
                servers.push(address);
            }
        }
    }
    servers
}

fn parse_server(token: &str) -> Option<SocketAddr> {
    if let Ok(address) = token.parse::<SocketAddr>() {
        return Some(address);
    }
    let literal = token
        .strip_prefix('[')
        .and_then(|text| text.strip_suffix(']'))
        .unwrap_or(token);
    literal
        .parse::<IpAddr>()
        .ok()
        .map(|ip| SocketAddr::new(ip, SYSTEM_DNS_PORT))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_and_bracketed_addresses_are_accepted() {
        let dns = SystemDns::default();
        dns.set("10.0.0.1\n[fd00::1]:53, 1.1.1.1:5353\n  fe80::1  ");
        let servers = dns.servers();
        assert_eq!(servers.len(), 4);
        assert!(servers.contains(&"10.0.0.1:53".parse().expect("v4")));
        assert!(servers.contains(&"[fd00::1]:53".parse().expect("v6")));
        assert!(servers.contains(&"1.1.1.1:5353".parse().expect("port")));
        assert!(servers.contains(&"[fe80::1]:53".parse().expect("scoped")));
    }

    #[test]
    fn duplicates_and_garbage_are_dropped() {
        let dns = SystemDns::default();
        dns.set("1.1.1.1, 1.1.1.1, nope, 0.0.0.0:0");
        assert_eq!(dns.servers(), vec!["1.1.1.1:53".parse().unwrap()]);
    }

    #[test]
    fn degraded_expires() {
        let dns = SystemDns::default();
        dns.set("1.1.1.1");
        assert!(!dns.is_degraded(0));
        dns.mark_degraded(1_000);
        assert!(dns.is_degraded(2_000));
        assert!(!dns.is_degraded(DEGRADED_WINDOW_NS + 1_001));
        dns.mark_degraded(1_000);
        dns.clear_degraded();
        assert!(!dns.is_degraded(2_000));
    }

    #[test]
    fn an_empty_list_is_never_degraded() {
        let dns = SystemDns::default();
        dns.mark_degraded(1_000);
        assert!(!dns.is_degraded(2_000));
        assert!(dns.is_empty());
    }
}

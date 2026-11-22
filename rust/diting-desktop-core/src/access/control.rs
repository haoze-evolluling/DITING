use std::collections::HashSet;
use std::fmt;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use diting_desktop_api::config::AccessControlConfig;

#[derive(Default)]
struct Compiled {
    allowed_ips: HashSet<IpAddr>,
    allowed_nets: Vec<Net>,
    blocked_ips: HashSet<IpAddr>,
    blocked_nets: Vec<Net>,
    has_allowed: bool,
    config: AccessControlConfig,
}

pub struct AccessControl {
    state: RwLock<Compiled>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AccessStats {
    pub allowed_entries: usize,
    pub blocked_entries: usize,
    pub has_allowed: bool,
}

impl AccessControl {
    pub fn new(config: &AccessControlConfig) -> Self {
        let control = Self {
            state: RwLock::new(Compiled::default()),
        };
        let _ = control.configure(config);
        control
    }

    pub fn configure(&self, config: &AccessControlConfig) -> Vec<String> {
        let mut problems = Vec::new();
        let mut allowed_ips = HashSet::new();
        let mut allowed_nets = Vec::new();
        let mut blocked_ips = HashSet::new();
        let mut blocked_nets = Vec::new();

        for raw in &config.allowed_clients {
            let entry = raw.trim();
            if entry.is_empty() {
                continue;
            }
            match parse_entry(entry) {
                Some(Parsed::Ip(ip)) => {
                    allowed_ips.insert(ip);
                }
                Some(Parsed::Net(net)) => allowed_nets.push(net),
                None => {
                    problems.push(format!("解析 allowedClients 条目 {entry:?} 失败，已跳过"));
                }
            }
        }

        for raw in &config.blocked_clients {
            let entry = raw.trim();
            if entry.is_empty() {
                continue;
            }
            match parse_entry(entry) {
                Some(Parsed::Ip(ip)) => {
                    blocked_ips.insert(ip);
                }
                Some(Parsed::Net(net)) => blocked_nets.push(net),
                None => {
                    problems.push(format!("解析 blockedClients 条目 {entry:?} 失败，已跳过"));
                }
            }
        }

        let has_allowed = !allowed_ips.is_empty() || !allowed_nets.is_empty();
        *self.write() = Compiled {
            allowed_ips,
            allowed_nets,
            blocked_ips,
            blocked_nets,
            has_allowed,
            config: config.clone(),
        };
        problems
    }

    pub fn check(&self, ip: Option<IpAddr>) -> (bool, String) {
        let Some(ip) = ip else {
            return (true, String::new());
        };
        let ip = normalize_ip(ip);
        let state = self.read();

        if state.blocked_ips.contains(&ip) {
            return (false, format!("客户端 IP {ip} 处于黑名单阻断列表中"));
        }
        for net in &state.blocked_nets {
            if net.contains(ip) {
                return (false, format!("客户端 IP {ip} 处于黑名单网段 {net} 中"));
            }
        }

        if state.has_allowed {
            if state.allowed_ips.contains(&ip) {
                return (true, String::new());
            }
            for net in &state.allowed_nets {
                if net.contains(ip) {
                    return (true, String::new());
                }
            }
            return (
                false,
                format!("客户端 IP {ip} 不在允许访问的 allowedClients 白名单列表中"),
            );
        }

        (true, String::new())
    }

    pub fn config(&self) -> AccessControlConfig {
        self.read().config.clone()
    }

    pub fn stats(&self) -> AccessStats {
        let state = self.read();
        AccessStats {
            allowed_entries: state.allowed_ips.len() + state.allowed_nets.len(),
            blocked_entries: state.blocked_ips.len() + state.blocked_nets.len(),
            has_allowed: state.has_allowed,
        }
    }

    fn read(&self) -> RwLockReadGuard<'_, Compiled> {
        self.state
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, Compiled> {
        self.state
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

enum Parsed {
    Ip(IpAddr),
    Net(Net),
}

fn parse_entry(text: &str) -> Option<Parsed> {
    if let Some((address, prefix)) = text.split_once('/') {
        let ip: IpAddr = address.parse().ok()?;
        let prefix: u8 = prefix.parse().ok()?;
        Net::from_network(ip, prefix).map(Parsed::Net)
    } else {
        Some(Parsed::Ip(normalize_ip(text.parse().ok()?)))
    }
}

fn normalize_ip(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => IpAddr::V6(v6),
        },
        IpAddr::V4(_) => ip,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Net {
    V4 { network: u32, prefix: u8 },
    V6 { network: u128, prefix: u8 },
}

impl Net {
    fn from_network(ip: IpAddr, prefix: u8) -> Option<Self> {
        match ip {
            IpAddr::V4(v4) => {
                if prefix > 32 {
                    return None;
                }
                Some(Net::V4 {
                    network: u32::from(v4) & mask32(prefix),
                    prefix,
                })
            }
            IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
                Some(v4) if prefix >= 96 => {
                    let prefix = prefix - 96;
                    Some(Net::V4 {
                        network: u32::from(v4) & mask32(prefix),
                        prefix,
                    })
                }
                _ => {
                    if prefix > 128 {
                        return None;
                    }
                    Some(Net::V6 {
                        network: u128::from(v6) & mask128(prefix),
                        prefix,
                    })
                }
            },
        }
    }

    fn contains(self, ip: IpAddr) -> bool {
        match (self, normalize_ip(ip)) {
            (Net::V4 { network, prefix }, IpAddr::V4(v4)) => {
                u32::from(v4) & mask32(prefix) == network
            }
            (Net::V6 { network, prefix }, IpAddr::V6(v6)) => {
                u128::from(v6) & mask128(prefix) == network
            }
            _ => false,
        }
    }
}

impl fmt::Display for Net {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match *self {
            Net::V4 { network, prefix } => {
                write!(formatter, "{}/{}", Ipv4Addr::from(network), prefix)
            }
            Net::V6 { network, prefix } => {
                write!(formatter, "{}/{}", Ipv6Addr::from(network), prefix)
            }
        }
    }
}

fn mask32(prefix: u8) -> u32 {
    if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - u32::from(prefix))
    }
}

fn mask128(prefix: u8) -> u128 {
    if prefix == 0 {
        0
    } else {
        u128::MAX << (128 - u32::from(prefix))
    }
}

//! Client IP to group resolution: longest-prefix matching.
//!
//! Ported from `client_groups.go`. Go sorted the compiled entries with
//! `sort.SliceStable` by descending prefix length, so the first match is the
//! longest prefix and equal-length entries keep declaration order. Rust's
//! `slice::sort_by` is stable, which reproduces the same tie-break.
//!
//! Entries are accepted as either a plain IP (`/32` or `/128`) or a CIDR. A
//! v4-mapped CIDR such as `::ffff:10.0.0.0/120` is folded to its four-byte
//! network (`10.0.0.0/24`), matching Go's `net.IPNet` collapse.

use std::net::IpAddr;

use diting_desktop_api::config::ClientGroup;

use super::DEFAULT_GROUP;

/// Fold `::ffff:a.b.c.d` into `a.b.c.d`, the equivalent of Go's `net.IP.To4`.
pub(crate) fn normalize_ip(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => IpAddr::V6(v6),
        },
        IpAddr::V4(_) => ip,
    }
}

/// One compiled membership entry.
#[derive(Clone, Debug)]
struct Entry {
    group: String,
    net: Net,
}

/// A network in the address family it compares as.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Net {
    V4 { network: u32, prefix: u8 },
    V6 { network: u128, prefix: u8 },
}

impl Net {
    /// Parses a CIDR, or a bare IP as a host route.
    fn parse_entry(text: &str) -> Option<Self> {
        let text = text.trim();
        if let Some((address, prefix)) = text.split_once('/') {
            let ip: IpAddr = address.parse().ok()?;
            let prefix: u8 = prefix.parse().ok()?;
            return Self::from_network(ip, prefix);
        }

        match normalize_ip(text.parse().ok()?) {
            IpAddr::V4(v4) => Some(Net::V4 {
                network: u32::from(v4),
                prefix: 32,
            }),
            IpAddr::V6(v6) => Some(Net::V6 {
                network: u128::from(v6),
                prefix: 128,
            }),
        }
    }

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
                // A mapped prefix keeps only the low four bytes, as `IPNet` does.
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

    fn prefix_len(self) -> u8 {
        match self {
            Net::V4 { prefix, .. } | Net::V6 { prefix, .. } => prefix,
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

/// Longest-prefix matcher compiled from the configured client groups.
pub struct GroupResolver {
    enabled: bool,
    entries: Vec<Entry>,
    groups: Vec<ClientGroup>,
}

impl GroupResolver {
    /// Compiles the enabled groups. Invalid members and unusable group ids are
    /// skipped and returned as diagnostics; the resolver stays usable.
    pub fn new(groups: &[ClientGroup], enabled: bool) -> (Self, Vec<String>) {
        let configured = groups.to_vec();
        if !enabled {
            return (
                Self {
                    enabled,
                    entries: Vec::new(),
                    groups: configured,
                },
                Vec::new(),
            );
        }

        let mut entries = Vec::new();
        let mut problems = Vec::new();
        for group in groups {
            if !group.enabled {
                continue;
            }
            let id = group.id.trim();
            if id.is_empty() || id == DEFAULT_GROUP {
                problems.push(format!(
                    "分组 {:?} 的 ID 为空或与默认组冲突，已跳过",
                    group.name
                ));
                continue;
            }
            for raw in &group.clients {
                match Net::parse_entry(raw) {
                    Some(net) => entries.push(Entry {
                        group: id.to_string(),
                        net,
                    }),
                    None => problems.push(format!("分组 {id} 的成员 {raw:?} 非法，已跳过")),
                }
            }
        }

        // Longest prefix first; `sort_by_key` is stable so equal lengths keep declaration order.
        entries.sort_by_key(|entry| std::cmp::Reverse(entry.net.prefix_len()));

        (
            Self {
                enabled,
                entries,
                groups: configured,
            },
            problems,
        )
    }

    /// Returns the matching group id, or `"default"`.
    pub fn resolve(&self, ip: IpAddr) -> String {
        if !self.enabled {
            return DEFAULT_GROUP.to_string();
        }
        self.entries
            .iter()
            .find(|entry| entry.net.contains(ip))
            .map(|entry| entry.group.clone())
            .unwrap_or_else(|| DEFAULT_GROUP.to_string())
    }

    /// The groups this resolver was configured with (including disabled ones).
    pub fn groups(&self) -> Vec<ClientGroup> {
        self.groups.clone()
    }
}

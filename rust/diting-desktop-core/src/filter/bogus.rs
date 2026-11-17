//! Bogus-NXDOMAIN detection (`bogus_nxdomain.go`).
//!
//! Some networks answer a non-existent name with a fixed navigation/advertising address instead of
//! NXDOMAIN. When `bogusNxDomain` is enabled, an A/AAAA answer inside the configured set is treated
//! as upstream hijacking and the DNS stage rewrites the response to NXDOMAIN.
//!
//! Entries accept single addresses and CIDR networks. Invalid entries are skipped while the rest of
//! the set stays usable, exactly like the Go matcher.

use std::net::IpAddr;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::filter::types::BogusNxDomainHit;

/// `maxBogusNXDomainNetworks`.
const MAX_ENTRIES: usize = 256;

/// One CIDR network.
#[derive(Debug, Clone, Copy)]
struct Network {
    base: IpAddr,
    prefix: u8,
}

impl Network {
    fn contains(&self, address: IpAddr) -> bool {
        match (self.base, address) {
            (IpAddr::V4(base), IpAddr::V4(address)) => {
                prefix_matches_v4(u32::from(base), u32::from(address), self.prefix)
            }
            (IpAddr::V6(base), IpAddr::V6(address)) => {
                prefix_matches_v6(u128::from(base), u128::from(address), self.prefix)
            }
            _ => false,
        }
    }
}

fn prefix_matches_v4(base: u32, address: u32, prefix: u8) -> bool {
    if prefix == 0 {
        return true;
    }
    if prefix > 32 {
        return false;
    }
    let mask = u32::MAX << (32 - prefix);
    base & mask == address & mask
}

fn prefix_matches_v6(base: u128, address: u128, prefix: u8) -> bool {
    if prefix == 0 {
        return true;
    }
    if prefix > 128 {
        return false;
    }
    let mask = u128::MAX << (128 - prefix);
    base & mask == address & mask
}

/// The compiled bogus-address set.
#[derive(Debug)]
pub(crate) struct BogusNXDomainMatcher {
    entries: Vec<String>,
    exact: Vec<IpAddr>,
    networks: Vec<Network>,
    hits: AtomicU64,
}

impl BogusNXDomainMatcher {
    /// Parses the list. The first invalid-entry message is returned alongside a usable matcher.
    pub(crate) fn new(entries: &[String]) -> (Self, Option<String>) {
        let mut matcher = Self {
            entries: Vec::new(),
            exact: Vec::new(),
            networks: Vec::new(),
            hits: AtomicU64::new(0),
        };
        let mut problems: Vec<String> = Vec::new();

        for raw in entries {
            let entry = raw.trim();
            if entry.is_empty() {
                continue;
            }
            if matcher.entries.len() >= MAX_ENTRIES {
                problems.push(format!("伪应答地址超过上限 {MAX_ENTRIES} 条，其余已忽略"));
                break;
            }

            if entry.contains('/') {
                match parse_cidr(entry) {
                    Ok(network) => {
                        matcher.networks.push(network);
                        matcher.entries.push(entry.to_string());
                    }
                    Err(error) => problems.push(error),
                }
                continue;
            }

            match entry.parse::<IpAddr>() {
                Ok(address) => {
                    matcher.exact.push(canonical(address));
                    matcher.entries.push(entry.to_string());
                }
                Err(_) => problems.push(format!("伪应答地址 {entry:?} 非法，已忽略")),
            }
        }

        let problem = if problems.is_empty() {
            None
        } else {
            Some(problems.join("; "))
        };
        (matcher, problem)
    }

    /// `MatchIP`, with Go's `net.IP.Equal` IPv4-mapped equivalence.
    pub(crate) fn matches(&self, address: IpAddr) -> bool {
        let address = canonical(address);
        if self.exact.contains(&address) {
            return true;
        }
        self.networks
            .iter()
            .any(|network| network.contains(address))
    }

    /// `FindInMsg`: first A/AAAA address that hits the set.
    pub(crate) fn find(&self, addresses: &[IpAddr]) -> Option<IpAddr> {
        if self.entries.is_empty() {
            return None;
        }
        for address in addresses {
            if self.matches(*address) {
                self.hits.fetch_add(1, Ordering::Relaxed);
                return Some(*address);
            }
        }
        None
    }

    /// The hit shape the DNS stage turns into an NXDOMAIN verdict.
    pub(crate) fn hit(&self, addresses: &[IpAddr]) -> Option<BogusNxDomainHit> {
        self.find(addresses).map(|ip| BogusNxDomainHit {
            ip,
            reason: format!("伪应答纠正: 解析为 {ip}，判定为上游劫持"),
        })
    }

    pub(crate) fn size(&self) -> usize {
        self.entries.len()
    }

    pub(crate) fn hits(&self) -> u64 {
        self.hits.load(Ordering::Relaxed)
    }
}

fn parse_cidr(entry: &str) -> Result<Network, String> {
    let (address, prefix) = entry
        .split_once('/')
        .ok_or_else(|| format!("伪应答网段 {entry:?} 非法，已忽略"))?;
    let base = address
        .parse::<IpAddr>()
        .map_err(|_| format!("伪应答网段 {entry:?} 非法，已忽略"))?;
    let prefix: u8 = prefix
        .parse()
        .map_err(|_| format!("伪应答网段 {entry:?} 非法，已忽略"))?;
    let max = if base.is_ipv4() { 32 } else { 128 };
    if prefix > max {
        return Err(format!("伪应答网段 {entry:?} 非法，已忽略"));
    }
    Ok(Network {
        base: canonical(base),
        prefix,
    })
}

/// Go's `net.IP.To4()` view: an IPv4-mapped IPv6 literal is the same host as its IPv4 form.
fn canonical(address: IpAddr) -> IpAddr {
    match address {
        IpAddr::V6(v6) => v6.to_ipv4_mapped().map_or(IpAddr::V6(v6), IpAddr::V4),
        IpAddr::V4(_) => address,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(text: &str) -> IpAddr {
        text.parse().expect("ip")
    }

    #[test]
    fn exact_and_cidr_entries_match() {
        let (matcher, problem) = BogusNXDomainMatcher::new(&[
            "203.0.113.7".to_string(),
            "198.51.100.0/24".to_string(),
            "2001:db8::/32".to_string(),
        ]);
        assert!(problem.is_none());
        assert!(matcher.matches(ip("203.0.113.7")));
        assert!(matcher.matches(ip("198.51.100.42")));
        assert!(matcher.matches(ip("2001:db8::1")));
        assert!(!matcher.matches(ip("8.8.8.8")));
        assert_eq!(matcher.size(), 3);
    }

    #[test]
    fn invalid_entries_are_reported_but_do_not_disable_the_set() {
        let (matcher, problem) = BogusNXDomainMatcher::new(&[
            "not-an-ip".to_string(),
            "10.0.0.0/99".to_string(),
            "10.0.0.1".to_string(),
        ]);
        assert!(problem.is_some());
        assert_eq!(matcher.size(), 1);
        assert!(matcher.matches(ip("10.0.0.1")));
    }

    #[test]
    fn find_returns_first_hit_and_counts_it() {
        let (matcher, _) = BogusNXDomainMatcher::new(&["127.0.0.1".to_string()]);
        let hit = matcher.hit(&[ip("8.8.8.8"), ip("127.0.0.1")]).expect("hit");
        assert_eq!(hit.ip, ip("127.0.0.1"));
        assert!(matcher.hit(&[ip("127.0.0.1")]).is_some());
        assert_eq!(matcher.hits(), 2);
    }

    #[test]
    fn ipv4_mapped_literals_compare_as_ipv4() {
        let (matcher, _) = BogusNXDomainMatcher::new(&["127.0.0.1".to_string()]);
        assert!(matcher.matches(ip("::ffff:127.0.0.1")));
    }
}

//! The hosts document parser and lookup table.
//!
//! This is a direct port of `rust/diting-hosts-core/src/hosts.rs` + `ip.rs` + `arpa.rs`. The
//! desktop crate does not depend on the kernel crate, so the parser lives here instead; the
//! observable behaviour (line comments, Unicode field splitting, the interface-zone cut, the
//! address forms `net.ParseIP` accepts, first-entry-wins deduplication) is kept identical.

use std::collections::BTreeMap;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::path::PathBuf;

/// `bufio.MaxScanTokenSize`: a longer line ends the scan for good.
const MAX_LINE_BYTES: usize = 64 * 1024;

/// One thing a table is built from.
#[derive(Debug, Clone)]
pub(crate) enum Source {
    /// Read as bytes; an unreadable path is skipped and remembered as the build error.
    File(PathBuf),
}

/// The parsed maps plus what happened while building them.
#[derive(Debug, Default, Clone)]
pub(crate) struct HostsTable {
    v4: BTreeMap<String, Vec<Ipv4Addr>>,
    v6: BTreeMap<String, Vec<Ipv6Addr>>,
    ptr: BTreeMap<IpAddr, Vec<String>>,
}

impl HostsTable {
    /// Builds a table from `sources`, in order. Returns the table, the paths that were read and
    /// the last read failure (the kernel's `info()` semantics).
    pub(crate) fn build(sources: &[Source]) -> (Self, Vec<String>, Option<String>) {
        let mut table = HostsTable::default();
        let mut loaded = Vec::new();
        let mut error = None;
        for source in sources {
            match source {
                Source::File(path) => {
                    let bytes = match std::fs::read(path) {
                        Ok(bytes) => bytes,
                        Err(err) => {
                            error = Some(format!("{}: {err}", path.display()));
                            continue;
                        }
                    };
                    table.parse(&String::from_utf8_lossy(&bytes));
                    loaded.push(path.display().to_string());
                }
            }
        }
        (table, loaded, error)
    }

    /// Builds a table from already-lightweight source paths, keeping the error for `reload`.
    pub(crate) fn build_paths(paths: &[String]) -> (Self, Vec<String>, Option<String>) {
        let sources: Vec<Source> = paths.iter().map(|path| Source::File(path.into())).collect();
        Self::build(&sources)
    }

    pub(crate) fn lookup(&self, host: &str, qtype: u16) -> Vec<IpAddr> {
        let host = normalize_host(host);
        match qtype {
            1 => self
                .v4
                .get(host.as_ref())
                .map(|ips| ips.iter().map(|ip| IpAddr::V4(*ip)).collect())
                .unwrap_or_default(),
            28 => self
                .v6
                .get(host.as_ref())
                .map(|ips| ips.iter().map(|ip| IpAddr::V6(*ip)).collect())
                .unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    pub(crate) fn has_domain(&self, host: &str) -> bool {
        let host = normalize_host(host);
        self.v4.contains_key(host.as_ref()) || self.v6.contains_key(host.as_ref())
    }

    pub(crate) fn ptr(&self, arpa_name: &str) -> Vec<String> {
        let Some(addr) = parse_arpa(arpa_name) else {
            return Vec::new();
        };
        self.ptr.get(&addr).cloned().unwrap_or_default()
    }

    /// Number of distinct names across the IPv4 and IPv6 maps.
    pub(crate) fn entry_count(&self) -> usize {
        let mut names = std::collections::BTreeSet::new();
        names.extend(self.v4.keys());
        names.extend(self.v6.keys());
        names.len()
    }

    fn parse(&mut self, text: &str) {
        for line in text.split('\n') {
            let line = line.strip_suffix('\r').unwrap_or(line);
            if line.len() > MAX_LINE_BYTES {
                return;
            }
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let line = match line.find('#') {
                Some(index) => line[..index].trim(),
                None => line,
            };
            let mut fields = line.split_whitespace();
            let Some(raw_address) = fields.next() else {
                continue;
            };
            let hosts: Vec<&str> = fields.collect();
            if hosts.is_empty() {
                continue;
            }
            let Some(addr) = parse_address(raw_address) else {
                continue;
            };
            for raw_host in hosts {
                let host = normalize_host(raw_host).into_owned();
                if host.is_empty() {
                    continue;
                }
                self.insert(addr, host);
            }
        }
    }

    fn insert(&mut self, addr: IpAddr, host: String) {
        match addr {
            IpAddr::V4(ip) => {
                let ips = self.v4.entry(host.clone()).or_default();
                if !ips.contains(&ip) {
                    ips.push(ip);
                }
            }
            IpAddr::V6(ip) => {
                let ips = self.v6.entry(host.clone()).or_default();
                if !ips.contains(&ip) {
                    ips.push(ip);
                }
            }
        }
        let names = self.ptr.entry(addr).or_default();
        if !names.contains(&host) {
            names.push(host);
        }
    }
}

/// `strings.ToLower(strings.Trim(host, "."))`.
pub(crate) fn normalize_host(host: &str) -> std::borrow::Cow<'_, str> {
    let trimmed = host.trim_matches('.');
    if trimmed.chars().any(|c| c.is_ascii_uppercase()) {
        std::borrow::Cow::Owned(trimmed.to_lowercase())
    } else {
        std::borrow::Cow::Borrowed(trimmed)
    }
}

/// `net.ParseIP` + `To4`, with the interface zone (`fe80::1%eth0`) cut first.
fn parse_address(raw: &str) -> Option<IpAddr> {
    let raw = match raw.find('%') {
        Some(index) => &raw[..index],
        None => raw,
    };
    if let Ok(v4) = raw.parse::<Ipv4Addr>() {
        return Some(IpAddr::V4(v4));
    }
    let v6 = raw.parse::<Ipv6Addr>().ok()?;
    Some(match v6.to_ipv4_mapped() {
        Some(v4) => IpAddr::V4(v4),
        None => IpAddr::V6(v6),
    })
}

/// `ParseIPFromArpa`: `None` for anything that is not a well-formed reverse name.
pub(crate) fn parse_arpa(name: &str) -> Option<IpAddr> {
    let lowered = name.to_lowercase();
    let trimmed = lowered.trim_end_matches('.').trim_start_matches('.');
    if let Some(prefix) = trimmed.strip_suffix(".in-addr.arpa") {
        let parts: Vec<&str> = prefix.split('.').collect();
        if parts.len() != 4 {
            return None;
        }
        let text = format!("{}.{}.{}.{}", parts[3], parts[2], parts[1], parts[0]);
        return text.parse::<Ipv4Addr>().ok().map(IpAddr::V4);
    }
    if let Some(prefix) = trimmed.strip_suffix(".ip6.arpa") {
        let nibbles: Vec<&str> = prefix.split('.').collect();
        if nibbles.len() != 32 {
            return None;
        }
        let mut bytes = [0u8; 16];
        for index in 0..16 {
            let low = nibble(nibbles[index * 2])?;
            let high = nibble(nibbles[index * 2 + 1])?;
            bytes[15 - index] = (high << 4) | low;
        }
        let v6 = Ipv6Addr::from(bytes);
        return Some(match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => IpAddr::V6(v6),
        });
    }
    None
}

fn nibble(label: &str) -> Option<u8> {
    let bytes = label.as_bytes();
    if bytes.len() != 1 {
        return None;
    }
    match bytes[0] {
        b'0'..=b'9' => Some(bytes[0] - b'0'),
        b'a'..=b'f' => Some(bytes[0] - b'a' + 10),
        b'A'..=b'F' => Some(bytes[0] - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_aliases_and_comments() {
        let mut table = HostsTable::default();
        table.parse(
            "# header\n127.0.0.1 localhost myapp.local\n192.168.1.100 nas.home storage.home # lan\n",
        );
        assert_eq!(
            table.lookup("myapp.local", 1),
            vec!["127.0.0.1".parse::<IpAddr>().unwrap()]
        );
        assert!(table.has_domain("storage.home"));
        assert!(!table.has_domain("missing.home"));
        let names = table.ptr("100.1.168.192.in-addr.arpa.");
        assert_eq!(names, vec!["nas.home", "storage.home"]);
    }

    #[test]
    fn strips_interface_zone_and_collapses_mapped_addresses() {
        let mut table = HostsTable::default();
        table.parse("fe80::1%eth0 link.local\n::ffff:10.0.0.1 mapped.local\n");
        assert_eq!(
            table.lookup("link.local", 28),
            vec!["fe80::1".parse::<Ipv6Addr>().unwrap()]
        );
        assert_eq!(
            table.lookup("mapped.local", 1),
            vec!["10.0.0.1".parse::<Ipv4Addr>().unwrap()]
        );
    }

    #[test]
    fn parses_arpa_names() {
        assert_eq!(
            parse_arpa("1.1.168.192.in-addr.arpa."),
            Some("192.168.1.1".parse().unwrap())
        );
        assert_eq!(
            parse_arpa("1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa."),
            Some("2001:db8::1".parse().unwrap())
        );
        assert_eq!(parse_arpa("invalid.in-addr.arpa"), None);
    }

    #[test]
    fn first_entry_wins_for_duplicates() {
        let mut table = HostsTable::default();
        table.parse("10.0.0.1 dup.local\n10.0.0.1 dup.local\n10.0.0.2 dup.local\n");
        assert_eq!(
            table.lookup("dup.local", 1),
            vec![
                "10.0.0.1".parse::<Ipv4Addr>().unwrap(),
                "10.0.0.2".parse::<Ipv4Addr>().unwrap()
            ]
        );
    }

    #[test]
    fn unreadable_file_is_reported_and_skipped() {
        let (table, loaded, error) =
            HostsTable::build_paths(&["definitely-missing-hosts-file".to_string()]);
        assert!(table.entry_count() == 0);
        assert!(loaded.is_empty());
        assert!(error.is_some());
    }
}

//! The hosts parser and the table it fills.
//!
//! The parser is a line-for-line port of `parseHostsReader`: trim the line, drop `#`-comments,
//! split on Unicode whitespace, cut the interface zone off the first field, parse the address,
//! then store it under every remaining field lowercased and stripped of dots. Duplicates are
//! dropped per host / per reverse name so the first entry wins, which is what the Go appends
//! guarded by `containsIP` / `containsString` did.
//!
//! Files are read here rather than in Go: the table is built from a source list, and
//! `UpdateConfig` / `Reload` swap the whole table instead of mutating one (the old code built the
//! new maps first for exactly that reason — see BUG-59 in `UpdateConfig`).

use std::collections::BTreeMap;
use std::path::PathBuf;

use diting_go_compat::text::{go_lower, go_trim_space};

use crate::arpa::parse_arpa;
use crate::ip::{parse_hosts_address, Addr};

/// `bufio.MaxScanTokenSize`: the old reader used `bufio.Scanner`, whose iterator stops for good on
/// a line longer than this. Emulated so a truncated file keeps behaving like a truncated file.
pub const MAX_LINE_BYTES: usize = 64 * 1024;

/// `dns.TypeA` / `dns.TypeAAAA`; the Go side passes the qtype straight through.
pub const TYPE_A: u16 = 1;
/// See [`TYPE_A`].
pub const TYPE_AAAA: u16 = 28;

/// One thing the table is built from: a file to read, or text the caller already has
/// (`LoadReader` in Go).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    /// Read as bytes; an unreadable path is skipped and remembered as the build error.
    File(PathBuf),
    /// Parsed as-is.
    Text(String),
}

/// The parsed hosts maps plus what happened while building them.
#[derive(Debug, Default)]
pub struct HostsTable {
    v4: BTreeMap<String, Vec<[u8; 4]>>,
    v6: BTreeMap<String, Vec<[u8; 16]>>,
    ptr: BTreeMap<Addr, Vec<String>>,
    loaded: Vec<String>,
    error: Option<String>,
}

impl HostsTable {
    /// Builds a table from `sources`, in order.
    pub fn build(sources: &[Source]) -> Self {
        let mut table = HostsTable::default();
        for source in sources {
            match source {
                Source::File(path) => {
                    let bytes = match std::fs::read(path) {
                        Ok(bytes) => bytes,
                        Err(err) => {
                            // The old code kept the last failure and carried on with the rest.
                            table.error = Some(format!("{}: {err}", path.display()));
                            continue;
                        }
                    };
                    table.parse(&String::from_utf8_lossy(&bytes));
                    table.loaded.push(path.display().to_string());
                }
                Source::Text(text) => table.parse(text),
            }
        }
        table
    }

    /// Paths that were read successfully, in order; `Reload` re-reads exactly these.
    pub fn loaded(&self) -> &[String] {
        &self.loaded
    }

    /// The last read failure, if any. `UpdateConfig` returns it; `New` ignored it.
    pub fn error(&self) -> Option<&str> {
        self.error.as_deref()
    }

    /// `Lookup`: the addresses stored for `host` under one qtype.
    pub fn lookup(&self, host: &str, qtype: u16) -> Vec<Addr> {
        let host = normalize_host(host);
        match qtype {
            TYPE_A => self
                .v4
                .get(host.as_ref())
                .map(|ips| ips.iter().map(|ip| Addr::V4(*ip)).collect())
                .unwrap_or_default(),
            TYPE_AAAA => self
                .v6
                .get(host.as_ref())
                .map(|ips| ips.iter().map(|ip| Addr::V6(*ip)).collect())
                .unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    /// `HasDomain`: whether any map holds this host, regardless of qtype.
    pub fn has_domain(&self, host: &str) -> bool {
        let host = normalize_host(host);
        self.v4.contains_key(host.as_ref()) || self.v6.contains_key(host.as_ref())
    }

    /// `LookupPTR`: reverse name in, host names out (in file order).
    pub fn ptr(&self, arpa_name: &str) -> Vec<String> {
        let Some(addr) = parse_arpa(arpa_name) else {
            return Vec::new();
        };
        self.ptr.get(&addr).cloned().unwrap_or_default()
    }

    /// `LookupReverse`: the first name registered for an address.
    pub fn reverse(&self, addr: &Addr) -> Option<&str> {
        self.ptr
            .get(addr)
            .and_then(|names| names.first())
            .map(String::as_str)
    }

    /// Appends one hosts document; used by [`HostsTable::build`] and by the parser tests.
    pub fn parse(&mut self, text: &str) {
        for line in text.split('\n') {
            // `bufio.Scanner` hands over the line without the `\n` and drops one `\r` in front of
            // it; a line past the token limit ends the iteration for good.
            let line = line.strip_suffix('\r').unwrap_or(line);
            if line.len() > MAX_LINE_BYTES {
                return;
            }
            let line = go_trim_space(line);
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let line = match line.find('#') {
                Some(index) => go_trim_space(&line[..index]),
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
            let Some(addr) = parse_hosts_address(raw_address) else {
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

    fn insert(&mut self, addr: Addr, host: String) {
        match addr {
            Addr::V4(bytes) => {
                let ips = self.v4.entry(host.clone()).or_default();
                if !ips.contains(&bytes) {
                    ips.push(bytes);
                }
            }
            Addr::V6(bytes) => {
                let ips = self.v6.entry(host.clone()).or_default();
                if !ips.contains(&bytes) {
                    ips.push(bytes);
                }
            }
        }
        let names = self.ptr.entry(addr).or_default();
        if !names.contains(&host) {
            names.push(host);
        }
    }
}

/// `strings.ToLower(strings.Trim(host, "."))`: dots only, not whitespace.
pub fn normalize_host(host: &str) -> std::borrow::Cow<'_, str> {
    go_lower(host.trim_matches('.'))
}

/// Parses one hosts document into a fresh table's worth of state; the tests use it directly.
pub fn parse_text(text: &str) -> HostsTable {
    let mut table = HostsTable::default();
    table.parse(text);
    table
}

#[cfg(test)]
mod tests;

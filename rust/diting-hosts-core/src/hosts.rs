use std::collections::BTreeMap;
use std::path::PathBuf;

use diting_go_compat::text::{go_lower, go_trim_space};

use crate::arpa::parse_arpa;
use crate::ip::{parse_hosts_address, Addr};

pub const MAX_LINE_BYTES: usize = 64 * 1024;

pub const TYPE_A: u16 = 1;
pub const TYPE_AAAA: u16 = 28;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    File(PathBuf),
    Text(String),
}

#[derive(Debug, Default)]
pub struct HostsTable {
    v4: BTreeMap<String, Vec<[u8; 4]>>,
    v6: BTreeMap<String, Vec<[u8; 16]>>,
    ptr: BTreeMap<Addr, Vec<String>>,
    loaded: Vec<String>,
    error: Option<String>,
}

impl HostsTable {
    pub fn build(sources: &[Source]) -> Self {
        let mut table = HostsTable::default();
        for source in sources {
            match source {
                Source::File(path) => {
                    let bytes = match std::fs::read(path) {
                        Ok(bytes) => bytes,
                        Err(err) => {
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

    pub fn loaded(&self) -> &[String] {
        &self.loaded
    }

    pub fn error(&self) -> Option<&str> {
        self.error.as_deref()
    }

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

    pub fn has_domain(&self, host: &str) -> bool {
        let host = normalize_host(host);
        self.v4.contains_key(host.as_ref()) || self.v6.contains_key(host.as_ref())
    }

    pub fn ptr(&self, arpa_name: &str) -> Vec<String> {
        let Some(addr) = parse_arpa(arpa_name) else {
            return Vec::new();
        };
        self.ptr.get(&addr).cloned().unwrap_or_default()
    }

    pub fn reverse(&self, addr: &Addr) -> Option<&str> {
        self.ptr
            .get(addr)
            .and_then(|names| names.first())
            .map(String::as_str)
    }

    pub fn parse(&mut self, text: &str) {
        for line in text.split('\n') {
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

pub fn normalize_host(host: &str) -> std::borrow::Cow<'_, str> {
    go_lower(host.trim_matches('.'))
}

pub fn parse_text(text: &str) -> HostsTable {
    let mut table = HostsTable::default();
    table.parse(text);
    table
}

#[cfg(test)]
mod tests;

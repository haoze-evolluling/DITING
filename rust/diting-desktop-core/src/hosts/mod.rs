mod parser;

use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::RwLock;

use diting_desktop_api::config::HostsConfig;

use parser::{HostsTable, Source};

pub const DEFAULT_HOSTS_TTL: u32 = 60;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostRecord {
    pub owner: String,
    pub qtype: u16,
    pub ip: IpAddr,
    pub ttl: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostsStats {
    pub enabled: bool,
    pub loaded_files: Vec<String>,
    pub error: Option<String>,
    pub entries: usize,
    pub ttl: u32,
}

struct HostsState {
    enabled: bool,
    ttl: u32,
    table: HostsTable,
    loaded_files: Vec<String>,
    error: Option<String>,
}

pub struct HostsResolver {
    state: RwLock<HostsState>,
}

impl HostsResolver {
    pub fn new(config: &HostsConfig) -> Self {
        let ttl = effective_ttl(config.ttl, DEFAULT_HOSTS_TTL);
        let (table, loaded_files, error) = build_from_config(config);
        Self {
            state: RwLock::new(HostsState {
                enabled: config.enabled,
                ttl,
                table,
                loaded_files,
                error,
            }),
        }
    }

    pub fn configure(&self, config: &HostsConfig) {
        let ttl = {
            let state = self.state.read().unwrap_or_else(|error| error.into_inner());
            effective_ttl(config.ttl, state.ttl)
        };
        let (table, loaded_files, error) = build_from_config(config);
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        *state = HostsState {
            enabled: config.enabled,
            ttl,
            table,
            loaded_files,
            error,
        };
    }

    pub fn reload(&self) -> Result<(), String> {
        let paths = {
            let state = self.state.read().unwrap_or_else(|error| error.into_inner());
            state.loaded_files.clone()
        };
        let (table, loaded_files, error) = HostsTable::build_paths(&paths);
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        state.table = table;
        state.loaded_files = loaded_files;
        state.error = error.clone();
        match error {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }

    pub fn enabled(&self) -> bool {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .enabled
    }

    pub fn ttl(&self) -> u32 {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .ttl
    }

    pub fn lookup(&self, domain: &str, qtype: u16) -> Vec<HostRecord> {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        if !state.enabled {
            return Vec::new();
        }
        let owner = fqdn(domain);
        state
            .table
            .lookup(domain, qtype)
            .into_iter()
            .map(|ip| HostRecord {
                owner: owner.clone(),
                qtype,
                ip,
                ttl: state.ttl,
            })
            .collect()
    }

    pub fn ptr(&self, arpa_name: &str) -> Vec<String> {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        if !state.enabled {
            return Vec::new();
        }
        state
            .table
            .ptr(arpa_name)
            .into_iter()
            .map(|name| fqdn(&name))
            .collect()
    }

    pub fn has_domain(&self, domain: &str) -> bool {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        state.enabled && state.table.has_domain(domain)
    }

    pub fn stats(&self) -> HostsStats {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        HostsStats {
            enabled: state.enabled,
            loaded_files: state.loaded_files.clone(),
            error: state.error.clone(),
            entries: state.table.entry_count(),
            ttl: state.ttl,
        }
    }
}

pub fn system_hosts_path() -> PathBuf {
    if cfg!(windows) {
        let root = std::env::var("SystemRoot").unwrap_or_else(|_| r"C:\Windows".to_string());
        PathBuf::from(root)
            .join("System32")
            .join("drivers")
            .join("etc")
            .join("hosts")
    } else {
        PathBuf::from("/etc/hosts")
    }
}

fn effective_ttl(requested: u32, fallback: u32) -> u32 {
    if requested > 0 {
        requested
    } else if fallback > 0 {
        fallback
    } else {
        DEFAULT_HOSTS_TTL
    }
}

fn build_from_config(config: &HostsConfig) -> (HostsTable, Vec<String>, Option<String>) {
    if !config.enabled {
        return (HostsTable::default(), Vec::new(), None);
    }
    let mut sources = Vec::with_capacity(config.custom_files.len() + 1);
    if config.use_system_host {
        sources.push(Source::File(system_hosts_path()));
    }
    for file in &config.custom_files {
        sources.push(Source::File(PathBuf::from(file)));
    }
    HostsTable::build(&sources)
}

fn fqdn(domain: &str) -> String {
    if domain.ends_with('.') {
        domain.to_string()
    } else {
        format!("{domain}.")
    }
}

#[cfg(test)]
mod tests;

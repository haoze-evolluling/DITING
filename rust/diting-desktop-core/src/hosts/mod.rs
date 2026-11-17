//! Local hosts-file resolver (`hosts_resolver.go`).
//!
//! The desktop crate does not link the `diting-hosts-core` kernel (it is not a dependency of this
//! crate), so the parser and lookup table are ported directly in [`parser`]. Configuration, TTL,
//! source selection and the atomic table swap keep the same shape as the Go facade: a new table is
//! built completely and then published under the write lock, so in-flight lookups never observe a
//! half-empty map.

mod parser;

use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::RwLock;

use diting_desktop_api::config::HostsConfig;

use parser::{HostsTable, Source};

/// `DefaultHostsTTL`: the TTL used when the config leaves it at zero.
pub const DEFAULT_HOSTS_TTL: u32 = 60;

/// One answer record produced by the hosts table.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostRecord {
    /// Owner name, fully qualified with a trailing dot (`dns.Fqdn`).
    pub owner: String,
    /// Numeric query type of this record (A or AAAA).
    pub qtype: u16,
    /// Address.
    pub ip: IpAddr,
    /// TTL applied by the resolver.
    pub ttl: u32,
}

/// Runtime state projection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostsStats {
    /// Whether the resolver answers queries.
    pub enabled: bool,
    /// Paths that were read successfully.
    pub loaded_files: Vec<String>,
    /// Last read failure, if any.
    pub error: Option<String>,
    /// Distinct domain names in the table.
    pub entries: usize,
    /// Effective TTL.
    pub ttl: u32,
}

struct HostsState {
    enabled: bool,
    ttl: u32,
    table: HostsTable,
    loaded_files: Vec<String>,
    error: Option<String>,
}

/// Local system and custom hosts-file resolver.
pub struct HostsResolver {
    state: RwLock<HostsState>,
}

impl HostsResolver {
    /// Creates a resolver and loads the configured sources.
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

    /// Rebuilds the table from `config` and swaps it in atomically.
    ///
    /// A read failure is stored in [`HostsStats::error`] instead of being returned, matching the
    /// Go `UpdateConfig` contract used by the service.
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

    /// Re-reads the files that were readable at the last build.
    ///
    /// Returns the read error, if any, after publishing the partially built table — the same
    /// behaviour as the Go `Reload`.
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

    /// Whether lookups answer.
    pub fn enabled(&self) -> bool {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .enabled
    }

    /// The effective TTL.
    pub fn ttl(&self) -> u32 {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .ttl
    }

    /// Forward lookup for A (1) or AAAA (28) queries.
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

    /// Reverse lookup: every alias registered for the address behind `arpa_name`, as FQDNs.
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

    /// Whether the table contains `domain`, regardless of record type.
    pub fn has_domain(&self, domain: &str) -> bool {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        state.enabled && state.table.has_domain(domain)
    }

    /// Runtime projection.
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

/// The platform hosts file: `%SystemRoot%\System32\drivers\etc\hosts` on Windows, `/etc/hosts`
/// elsewhere.
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
        // Relative paths are intentionally accepted as-is (relative to the service cwd).
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

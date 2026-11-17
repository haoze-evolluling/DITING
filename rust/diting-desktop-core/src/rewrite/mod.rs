//! Custom DNS rewrite engine (`rewrite.go`, `rewrite_records.go`, `rewrite_lookup.go`).
//!
//! `diting-rewrite-core` owns matching, the shortcut/explicit record compilation, PTR indexing,
//! rcode overrides and the CNAME chase. This facade keeps the API rule list (the JSON shape the
//! IPC surface persists and serves), converts it to the kernel's [`RuleConfig`] and publishes a
//! fresh kernel snapshot on every mutation by swapping it under the write lock.

use std::net::IpAddr;
use std::sync::RwLock;

use diting_desktop_api::config::{RewriteConfig, RewriteRule};
use diting_rewrite_core::engine::{
    normalize_domain, Config as KernelConfig, LookupResult, RecordSpec, RuleConfig,
};
use diting_rewrite_core::Engine;

/// `DefaultRewriteTTL`.
pub const DEFAULT_REWRITE_TTL: u32 = 60;

/// Runtime projection.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteStats {
    /// Whether lookups are enabled.
    pub enabled: bool,
    /// Number of retained rules.
    pub rule_count: usize,
    /// Warnings emitted while compiling the current snapshot.
    pub warnings: Vec<String>,
}

struct Compiled {
    enabled: bool,
    default_ttl: u32,
    rules: Vec<RewriteRule>,
    kernel: Engine,
    warnings: Vec<String>,
}

/// Custom DNS rewrite engine.
pub struct RewriteEngine {
    state: RwLock<Compiled>,
}

impl RewriteEngine {
    /// Creates an engine from `config`.
    pub fn new(config: &RewriteConfig) -> Self {
        let default_ttl = if config.ttl == 0 {
            DEFAULT_REWRITE_TTL
        } else {
            config.ttl
        };
        let rules = retain_rules(&config.rules);
        let (kernel, warnings) = build_kernel(config.enabled, default_ttl, &rules);
        Self {
            state: RwLock::new(Compiled {
                enabled: config.enabled,
                default_ttl,
                rules,
                kernel,
                warnings,
            }),
        }
    }

    /// Rebuilds the snapshot from `config`, returning the compiler warnings.
    pub fn configure(&self, config: &RewriteConfig) -> Vec<String> {
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        // A zero TTL keeps the previously effective default, like the Go `Configure`.
        let default_ttl = if config.ttl > 0 {
            config.ttl
        } else {
            state.default_ttl
        };
        let rules = retain_rules(&config.rules);
        let (kernel, warnings) = build_kernel(config.enabled, default_ttl, &rules);
        *state = Compiled {
            enabled: config.enabled,
            default_ttl,
            rules,
            kernel,
            warnings: warnings.clone(),
        };
        warnings
    }

    /// Whether lookups answer.
    pub fn enabled(&self) -> bool {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .enabled
    }

    /// Looks `domain` up for `qtype`.
    pub fn lookup(&self, domain: &str, qtype: u16) -> LookupResult {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .kernel
            .lookup(domain, qtype)
    }

    /// PTR targets registered for `ip`, in configuration order.
    pub fn lookup_ptr(&self, ip: IpAddr) -> Vec<String> {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        if !state.enabled {
            return Vec::new();
        }
        let bytes = ip_bytes(ip);
        state.kernel.lookup_ptr(&bytes)
    }

    /// The retained API rule list.
    pub fn rules(&self) -> Vec<RewriteRule> {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .rules
            .clone()
    }

    /// Replaces the whole rule list. Empty-domain rules are dropped, like the Go configure path.
    pub fn set_rules(&self, rules: Vec<RewriteRule>) {
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        let rules = retain_rules(&rules);
        let (kernel, warnings) = build_kernel(state.enabled, state.default_ttl, &rules);
        state.kernel = kernel;
        state.rules = rules;
        state.warnings = warnings;
    }

    /// Adds one rule, replacing any rule with the same normalized domain.
    pub fn add_rule(&self, rule: RewriteRule) -> Result<(), String> {
        let normalized = normalize_domain(&rule.domain);
        if normalized.is_empty() {
            return Err("无效的重写域名".to_string());
        }
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        let mut rules: Vec<RewriteRule> = state
            .rules
            .iter()
            .filter(|existing| normalize_domain(&existing.domain) != normalized)
            .cloned()
            .collect();
        rules.push(rule);
        let (kernel, warnings) = build_kernel(state.enabled, state.default_ttl, &rules);
        state.kernel = kernel;
        state.rules = rules;
        state.warnings = warnings;
        Ok(())
    }

    /// Deletes every rule matching `domain`, erroring when none exists.
    pub fn delete_rule(&self, domain: &str) -> Result<(), String> {
        let normalized = normalize_domain(domain);
        if normalized.is_empty() {
            return Err("无效的重写域名".to_string());
        }
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
        let mut found = false;
        let rules: Vec<RewriteRule> = state
            .rules
            .iter()
            .filter(|existing| {
                let keep = normalize_domain(&existing.domain) != normalized;
                found |= !keep;
                keep
            })
            .cloned()
            .collect();
        if !found {
            return Err(format!("未找到域名 {domain:?} 的重写规则"));
        }
        let (kernel, warnings) = build_kernel(state.enabled, state.default_ttl, &rules);
        state.kernel = kernel;
        state.rules = rules;
        state.warnings = warnings;
        Ok(())
    }

    /// Runtime projection.
    pub fn stats(&self) -> RewriteStats {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        RewriteStats {
            enabled: state.enabled,
            rule_count: state.rules.len(),
            warnings: state.warnings.clone(),
        }
    }
}

/// Drops rules whose normalized domain is empty; those never enter the kernel index nor the
/// list returned over IPC (the Go `retainRewriteRules` behaviour).
fn retain_rules(rules: &[RewriteRule]) -> Vec<RewriteRule> {
    rules
        .iter()
        .filter(|rule| !normalize_domain(&rule.domain).is_empty())
        .cloned()
        .collect()
}

fn build_kernel(enabled: bool, default_ttl: u32, rules: &[RewriteRule]) -> (Engine, Vec<String>) {
    let kernel_rules = rules
        .iter()
        .map(|rule| RuleConfig {
            domain: rule.domain.clone(),
            ips: rule.ips.clone(),
            cname: rule.cname.clone(),
            txt: rule.txt.clone(),
            ttl: rule.ttl,
            records: rule
                .records
                .iter()
                .map(|record| RecordSpec {
                    type_name: record.kind.clone(),
                    value: record.value.clone(),
                })
                .collect(),
            rcode: rule.rcode.clone(),
        })
        .collect();
    Engine::build(&KernelConfig {
        enabled,
        default_ttl,
        rules: kernel_rules,
    })
}

/// Go passes `net.IP.ToString`-style bytes with `To4` applied; the kernel collapses mapped
/// addresses itself, so a 16-byte V6 form is fine too.
fn ip_bytes(ip: IpAddr) -> Vec<u8> {
    match ip {
        IpAddr::V4(address) => address.octets().to_vec(),
        IpAddr::V6(address) => address.octets().to_vec(),
    }
}

#[cfg(test)]
mod tests;

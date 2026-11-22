use std::net::IpAddr;
use std::sync::RwLock;

use diting_desktop_api::config::{RewriteConfig, RewriteRule};
use diting_rewrite_core::engine::{
    normalize_domain, Config as KernelConfig, LookupResult, RecordSpec, RuleConfig,
};
use diting_rewrite_core::Engine;

pub const DEFAULT_REWRITE_TTL: u32 = 60;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteStats {
    pub enabled: bool,
    pub rule_count: usize,
    pub warnings: Vec<String>,
}

struct Compiled {
    enabled: bool,
    default_ttl: u32,
    rules: Vec<RewriteRule>,
    kernel: Engine,
    warnings: Vec<String>,
}

pub struct RewriteEngine {
    state: RwLock<Compiled>,
}

impl RewriteEngine {
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

    pub fn configure(&self, config: &RewriteConfig) -> Vec<String> {
        let mut state = self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner());
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

    pub fn enabled(&self) -> bool {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .enabled
    }

    pub fn lookup(&self, domain: &str, qtype: u16) -> LookupResult {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .kernel
            .lookup(domain, qtype)
    }

    pub fn lookup_ptr(&self, ip: IpAddr) -> Vec<String> {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        if !state.enabled {
            return Vec::new();
        }
        let bytes = ip_bytes(ip);
        state.kernel.lookup_ptr(&bytes)
    }

    pub fn rules(&self) -> Vec<RewriteRule> {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .rules
            .clone()
    }

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

    pub fn stats(&self) -> RewriteStats {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        RewriteStats {
            enabled: state.enabled,
            rule_count: state.rules.len(),
            warnings: state.warnings.clone(),
        }
    }
}

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

fn ip_bytes(ip: IpAddr) -> Vec<u8> {
    match ip {
        IpAddr::V4(address) => address.octets().to_vec(),
        IpAddr::V6(address) => address.octets().to_vec(),
    }
}

#[cfg(test)]
mod tests;

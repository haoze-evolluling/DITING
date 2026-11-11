//! `ApplyDNSConfig`'s validation pass, in one kernel call.
//!
//! The old code normalized and validated in a fixed order, and the error that surfaced was the first
//! one that failed: mode, then "no providers", then the single-mode provider count, then each
//! provider (protocol, then its endpoint). That order is user-visible — a config with both a bad
//! mode and a bad provider reports the mode — so it is reproduced here rather than in the caller.

use crate::dynamic::DynamicBlock;
use crate::endpoint::validate_provider;
use crate::mode::canonical_dns_mode;
use crate::protocol::{parse_response_type_upper, Protocol, ResponseType};

/// One incoming provider, exactly the JSON fields `dnsProviderConfig` carries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub id: String,
    pub protocol: String,
    pub server: String,
    pub url: String,
    pub weight: i64,
}

/// One provider after normalization: the protocol name upper-cased and resolved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedProvider {
    pub id: String,
    pub protocol: Protocol,
    pub server: String,
    pub url: String,
    pub weight: i64,
}

/// The whole normalized config.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedConfig {
    pub mode: &'static str,
    pub block_response: ResponseType,
    pub dynamic: DynamicBlock,
    pub providers: Vec<NormalizedProvider>,
}

/// Normalizes and validates a DNS config; the error is the text `ApplyDNSConfig` returned.
pub fn normalize(
    mode: &str,
    block_response: &str,
    dynamic: DynamicBlock,
    providers: &[Provider],
) -> Result<NormalizedConfig, String> {
    let mode = canonical_dns_mode(mode)?;

    if providers.is_empty() {
        return Err("DNS config has no providers".to_string());
    }
    if mode == crate::mode::MODE_SINGLE && providers.len() != 1 {
        return Err("single DNS mode requires exactly one provider".to_string());
    }

    let mut normalized = Vec::with_capacity(providers.len());
    for (index, provider) in providers.iter().enumerate() {
        let protocol = validate_provider(&provider.protocol, &provider.server, &provider.url)
            .map_err(|err| format!("provider {index}: {err}"))?;
        normalized.push(NormalizedProvider {
            id: provider.id.clone(),
            protocol,
            server: provider.server.clone(),
            url: provider.url.clone(),
            weight: provider.weight,
        });
    }

    Ok(NormalizedConfig {
        mode,
        // `ApplyDNSConfig` upper-cased the value before parsing it; `SetBlockResponseType` does not.
        block_response: parse_response_type_upper(block_response),
        dynamic,
        providers: normalized,
    })
}

#[cfg(test)]
mod tests;

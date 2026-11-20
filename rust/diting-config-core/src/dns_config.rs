use crate::dynamic::DynamicBlock;
use crate::endpoint::validate_provider;
use crate::mode::canonical_dns_mode;
use crate::protocol::{parse_response_type_upper, Protocol, ResponseType};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub id: String,
    pub protocol: String,
    pub server: String,
    pub url: String,
    pub weight: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedProvider {
    pub id: String,
    pub protocol: Protocol,
    pub server: String,
    pub url: String,
    pub weight: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedConfig {
    pub mode: &'static str,
    pub block_response: ResponseType,
    pub dynamic: DynamicBlock,
    pub providers: Vec<NormalizedProvider>,
}

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
        block_response: parse_response_type_upper(block_response),
        dynamic,
        providers: normalized,
    })
}

#[cfg(test)]
mod tests;

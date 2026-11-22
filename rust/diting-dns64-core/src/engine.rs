use crate::addr::to4;
use crate::prefix::{
    is_unspecified, parse_cidr, parse_dns64_prefix, well_known_prefix, Net, Prefix, PrefixError,
};

const DEFAULT_EXCLUSIONS: [&str; 3] = ["::ffff:0:0/96", "::1/128", "fe80::/10"];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixRejection {
    pub index: usize,
    pub error: PrefixError,
}

#[derive(Debug)]
pub struct Engine {
    enabled: bool,
    prefixes: Vec<Prefix>,
    exclusions: Vec<Net>,
}

impl Engine {
    pub fn new(enabled: bool, prefixes: &[String]) -> Result<Engine, PrefixRejection> {
        let mut exclusions = Vec::with_capacity(DEFAULT_EXCLUSIONS.len() + prefixes.len());
        for text in DEFAULT_EXCLUSIONS {
            if let Ok(cidr) = parse_cidr(text) {
                exclusions.push(cidr.net);
            }
        }

        let mut parsed = Vec::with_capacity(prefixes.len());
        for (index, raw) in prefixes.iter().enumerate() {
            let text = diting_go_compat::text::go_trim_space(raw);
            if text.is_empty() {
                continue;
            }
            match parse_dns64_prefix(text) {
                Ok((prefix, net)) => {
                    parsed.push(prefix);
                    exclusions.push(net);
                }
                Err(error) => {
                    return Err(PrefixRejection { index, error });
                }
            }
        }

        Ok(Engine {
            enabled,
            prefixes: parsed,
            exclusions,
        })
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    pub fn prefix_count(&self) -> usize {
        self.prefixes.len()
    }

    pub fn map(&self, v4: [u8; 4]) -> [u8; 16] {
        match self.prefixes.first() {
            Some(prefix) => prefix.embed(v4),
            None => well_known_prefix().embed(v4),
        }
    }

    pub fn synthesize(&self, v4: Option<[u8; 4]>) -> Vec<[u8; 16]> {
        if !self.enabled {
            return Vec::new();
        }
        let Some(v4) = v4 else {
            return Vec::new();
        };
        if self.prefixes.is_empty() {
            return vec![well_known_prefix().embed(v4)];
        }
        self.prefixes
            .iter()
            .map(|prefix| prefix.embed(v4))
            .collect()
    }

    pub fn excluded(&self, bytes: &[u8]) -> bool {
        if is_unspecified(bytes) {
            return true;
        }
        self.exclusions.iter().any(|net| net.contains(bytes))
    }

    pub fn has_valid_aaaa(&self, addresses: &[&[u8]]) -> bool {
        addresses.iter().any(|bytes| !self.excluded(bytes))
    }
}

pub fn fold_v4(bytes: &[u8]) -> Option<[u8; 4]> {
    to4(bytes)
}

#[cfg(test)]
mod tests;

//! The DNS64 synthesizer: RFC 6052 embedding, the RFC 6147 exclusion set, and the AAAA check that
//! decides whether synthesis may run at all.
//!
//! The Go side keeps the parts that need `dns.Msg` or the resolver: querying A records, the
//! minimum-TTL walk over A / CNAME / DNAME answers, deduping against the existing answer section,
//! and building the `dns.AAAA` records. Everything here is pure address arithmetic, so it is
//! driven by an injectable nothing — no clock, no I/O, no locks.

use crate::addr::to4;
use crate::prefix::{
    is_unspecified, parse_cidr, parse_dns64_prefix, well_known_prefix, Net, Prefix, PrefixError,
};

/// The default exclusions from RFC 6147 section 5.1.4, in the order the old code added them.
const DEFAULT_EXCLUSIONS: [&str; 3] = ["::ffff:0:0/96", "::1/128", "fe80::/10"];

/// A configured prefix that the kernel refused, and where it sits in the list.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixRejection {
    pub index: usize,
    pub error: PrefixError,
}

/// One synthesizer instance — the Go side swaps the whole handle on `UpdateConfig`, so the state
/// here is immutable once built.
#[derive(Debug)]
pub struct Engine {
    enabled: bool,
    prefixes: Vec<Prefix>,
    exclusions: Vec<Net>,
}

impl Engine {
    /// Builds an instance; `prefixes` are the raw configured strings, trimmed here the way the old
    /// constructor trimmed them, and blank entries skipped.
    pub fn new(enabled: bool, prefixes: &[String]) -> Result<Engine, PrefixRejection> {
        let mut exclusions = Vec::with_capacity(DEFAULT_EXCLUSIONS.len() + prefixes.len());
        for text in DEFAULT_EXCLUSIONS {
            // These are compiled in and parse; `net.ParseCIDR` failures were skipped silently.
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
                    // A configured prefix is excluded too, so a second synthesis pass cannot
                    // recurse into an address this kernel just produced.
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

    /// Whether synthesis may produce anything at all.
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// How many prefixes synthesis uses.
    pub fn prefix_count(&self) -> usize {
        self.prefixes.len()
    }

    /// `MapIPv4ToIPv6`: embeds behind the first configured prefix, falling back to the well-known
    /// one when the configured list is empty (every entry was blank).
    pub fn map(&self, v4: [u8; 4]) -> [u8; 16] {
        match self.prefixes.first() {
            Some(prefix) => prefix.embed(v4),
            None => well_known_prefix().embed(v4),
        }
    }

    /// `SynthesizeFromAWithTTL` minus the TTLs: the AAAA addresses for one A record, one per
    /// prefix in configuration order. `None` is an A record without an IPv4 address, which the old
    /// loop skipped.
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

    /// `IsExcluded`. `bytes` comes straight from Go, so 4-byte and 16-byte shapes both show up;
    /// an empty slice is the non-nil empty `net.IP`, which the old code did *not* treat as
    /// unspecified. A nil interface is handled by the caller.
    pub fn excluded(&self, bytes: &[u8]) -> bool {
        if is_unspecified(bytes) {
            return true;
        }
        self.exclusions.iter().any(|net| net.contains(bytes))
    }

    /// `HasValidAAAARecords` over already-extracted addresses: an AAAA answer that survives the
    /// exclusion set means the response is usable as is.
    pub fn has_valid_aaaa(&self, addresses: &[&[u8]]) -> bool {
        addresses.iter().any(|bytes| !self.excluded(bytes))
    }
}

/// `IP.To4()` on a Go address, exposed for the payload layer.
pub fn fold_v4(bytes: &[u8]) -> Option<[u8; 4]> {
    to4(bytes)
}

#[cfg(test)]
mod tests;

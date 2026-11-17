//! Local authoritative zones (`custom_zone.go`).
//!
//! Unlike hosts and rewrite, a zone is *authoritative*: every name at or below the apex belongs to
//! the local engine, so a missing name is answered locally (NXDOMAIN / NODATA) instead of leaking
//! to an upstream. The index is a global name map plus a longest-origin list; every rebuild is
//! published as one `RwLock` swap.

mod parser;
mod records;

use std::collections::HashMap;
use std::sync::RwLock;

use diting_desktop_api::config::ZoneConfig;

use parser::{parse_zone, ParsedZone};
use records::{is_domain_name, label_count};
pub use records::{ZoneRData, ZoneRecord, TYPE_ANY, TYPE_CNAME, TYPE_SOA};

/// Maximum number of configured zones.
pub const MAX_ZONE_COUNT: usize = 32;
/// Maximum number of IN records across all zones.
pub const MAX_ZONE_RECORDS: usize = 10_000;
/// Maximum bytes of one zone's text (1 MiB).
pub const MAX_ZONE_CONTENT_BYTES: usize = 1 << 20;
/// Default TTL when the configuration leaves it at zero.
pub const DEFAULT_ZONE_TTL: u32 = 300;
/// `RCODE_NXDOMAIN`.
pub const RCODE_NXDOMAIN: u16 = 3;

/// The result of one authoritative lookup.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZoneAnswer {
    /// `true` when the name belongs to a configured zone.
    pub matched: bool,
    /// Response code: 0 for a positive answer or NODATA, [`RCODE_NXDOMAIN`] for a missing name.
    pub rcode: u16,
    /// Answer records.
    pub answers: Vec<ZoneRecord>,
    /// Negative-answer SOA (empty for positive answers).
    pub authority: Vec<ZoneRecord>,
}

/// Per-zone build result for the UI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZoneState {
    pub id: String,
    pub origin: String,
    pub records: usize,
    pub loaded: bool,
    pub error: Option<String>,
}

struct Compiled {
    enabled: bool,
    default_ttl: u32,
    records: HashMap<String, HashMap<u16, Vec<ZoneRecord>>>,
    soa_by_origin: HashMap<String, ZoneRecord>,
    /// Apexes ordered by label count, longest suffix first.
    origins: Vec<String>,
    states: Vec<ZoneState>,
}

/// Local authoritative-zone engine.
pub struct ZoneEngine {
    state: RwLock<Compiled>,
}

impl ZoneEngine {
    /// Creates and builds the engine.
    pub fn new(config: &ZoneConfig) -> Self {
        Self {
            state: RwLock::new(build(config, 0)),
        }
    }

    /// Rebuilds the index from `config`.
    pub fn configure(&self, config: &ZoneConfig) {
        let previous_ttl = self
            .state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .default_ttl;
        let compiled = build(config, previous_ttl);
        *self
            .state
            .write()
            .unwrap_or_else(|error| error.into_inner()) = compiled;
    }

    /// Whether lookups answer.
    pub fn enabled(&self) -> bool {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .enabled
    }

    /// Queries the local zones.
    pub fn lookup(&self, domain: &str, qtype: u16) -> ZoneAnswer {
        let state = self.state.read().unwrap_or_else(|error| error.into_inner());
        let unmatched = ZoneAnswer {
            matched: false,
            rcode: 0,
            answers: Vec::new(),
            authority: Vec::new(),
        };
        if !state.enabled {
            return unmatched;
        }
        let Some(name) = query_name(domain) else {
            return unmatched;
        };
        let Some(origin) = state.authoritative_origin(&name) else {
            return unmatched;
        };
        let soa = state.soa_for(&origin);

        let Some(by_type) = state.records.get(&name).filter(|map| !map.is_empty()) else {
            // The name is inside a local zone but the zone never declared it: authoritative
            // NXDOMAIN, never an upstream query.
            return ZoneAnswer {
                matched: true,
                rcode: RCODE_NXDOMAIN,
                answers: Vec::new(),
                authority: vec![soa],
            };
        };

        if qtype == TYPE_ANY {
            let mut answers = Vec::new();
            let mut types: Vec<u16> = by_type.keys().copied().collect();
            types.sort_unstable();
            for rtype in types {
                answers.extend(by_type[&rtype].iter().cloned());
            }
            return ZoneAnswer {
                matched: true,
                rcode: 0,
                answers,
                authority: Vec::new(),
            };
        }

        if let Some(records) = by_type.get(&qtype).filter(|records| !records.is_empty()) {
            return ZoneAnswer {
                matched: true,
                rcode: 0,
                answers: records.clone(),
                authority: Vec::new(),
            };
        }

        let cnames = by_type.get(&TYPE_CNAME).cloned().unwrap_or_default();
        if qtype == TYPE_CNAME || cnames.is_empty() {
            return nodata(soa);
        }

        let mut answers = Vec::new();
        let mut visited = std::collections::HashSet::new();
        visited.insert(name);
        for cname in &cnames {
            answers.push(cname.clone());
            if let ZoneRData::Cname(target) = &cname.rdata {
                state.chase(target, qtype, &mut visited, &mut answers);
            }
        }
        if answers.len() == cnames.len() {
            // Only the CNAME itself, no record of the requested type: authoritative NODATA.
            return nodata(soa);
        }
        ZoneAnswer {
            matched: true,
            rcode: 0,
            answers,
            authority: Vec::new(),
        }
    }

    /// Per-zone build states.
    pub fn states(&self) -> Vec<ZoneState> {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .states
            .clone()
    }

    /// Effective default TTL.
    pub fn default_ttl(&self) -> u32 {
        self.state
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .default_ttl
    }
}

impl Compiled {
    fn authoritative_origin(&self, name: &str) -> Option<String> {
        self.origins.iter().find_map(|origin| {
            if origin == "." || name == origin || name.ends_with(&format!(".{origin}")) {
                Some(origin.clone())
            } else {
                None
            }
        })
    }

    /// The explicit apex SOA, or the synthesised one the Go engine built for negative answers.
    fn soa_for(&self, origin: &str) -> ZoneRecord {
        if let Some(soa) = self.soa_by_origin.get(origin) {
            return soa.clone();
        }
        ZoneRecord {
            owner: origin.to_string(),
            rtype: TYPE_SOA,
            ttl: self.default_ttl,
            rdata: ZoneRData::Soa {
                mname: "localhost.".to_string(),
                rname: "nobody.invalid.".to_string(),
                serial: 1,
                refresh: 10_000,
                retry: 2_400,
                expire: 604_800,
                minimum: self.default_ttl,
            },
        }
    }

    /// Follows in-zone CNAMEs for `qtype`. The visited set and depth limit are the Go bounds.
    fn chase(
        &self,
        target: &str,
        qtype: u16,
        visited: &mut std::collections::HashSet<String>,
        out: &mut Vec<ZoneRecord>,
    ) {
        if visited.len() > 8 {
            return;
        }
        let Some(name) = query_name(target) else {
            return;
        };
        if visited.contains(&name) {
            return;
        }
        visited.insert(name.clone());
        if self.authoritative_origin(&name).is_none() {
            return;
        }
        let Some(by_type) = self.records.get(&name) else {
            return;
        };
        if let Some(records) = by_type.get(&qtype).filter(|records| !records.is_empty()) {
            out.extend(records.iter().cloned());
            return;
        }
        let mut chained = Vec::new();
        for cname in by_type.get(&TYPE_CNAME).into_iter().flatten() {
            chained.push(cname.clone());
            if let ZoneRData::Cname(target) = &cname.rdata {
                self.chase(target, qtype, visited, &mut chained);
            }
        }
        out.extend(chained);
    }
}

fn nodata(soa: ZoneRecord) -> ZoneAnswer {
    ZoneAnswer {
        matched: true,
        rcode: 0,
        answers: Vec::new(),
        authority: vec![soa],
    }
}

fn query_name(domain: &str) -> Option<String> {
    let lowered = domain.trim().to_lowercase();
    if lowered.is_empty() {
        return None;
    }
    let name = if lowered.ends_with('.') {
        lowered
    } else {
        format!("{lowered}.")
    };
    is_domain_name(&name).then_some(name)
}

fn build(config: &ZoneConfig, previous_ttl: u32) -> Compiled {
    let default_ttl = if config.ttl > 0 {
        config.ttl
    } else if previous_ttl > 0 {
        previous_ttl
    } else {
        DEFAULT_ZONE_TTL
    };
    let mut records: HashMap<String, HashMap<u16, Vec<ZoneRecord>>> = HashMap::new();
    let mut soa_by_origin = HashMap::new();
    let mut origins = Vec::new();
    let mut states = Vec::with_capacity(config.zones.len());
    let mut budget = MAX_ZONE_RECORDS;

    for (index, entry) in config.zones.iter().enumerate() {
        let mut state = ZoneState {
            id: entry.id.clone(),
            origin: entry.origin.clone(),
            records: 0,
            loaded: false,
            error: None,
        };
        if index >= MAX_ZONE_COUNT {
            state.error = Some(format!("超出区数量上限 {MAX_ZONE_COUNT}，未加载"));
            states.push(state);
            continue;
        }
        if !entry.enabled {
            state.error = Some("已停用".to_string());
            states.push(state);
            continue;
        }
        if entry.content.len() > MAX_ZONE_CONTENT_BYTES {
            state.error = Some(format!(
                "区文本 {} 字节超出上限 {} 字节",
                entry.content.len(),
                MAX_ZONE_CONTENT_BYTES
            ));
            states.push(state);
            continue;
        }
        if budget == 0 {
            state.error = Some(format!("已达记录总数上限 {MAX_ZONE_RECORDS}，未加载"));
            states.push(state);
            continue;
        }

        let parsed = match parse_zone(&entry.origin, &entry.content, default_ttl, budget) {
            Ok(parsed) => parsed,
            Err(error) => {
                state.error = Some(error);
                states.push(state);
                continue;
            }
        };
        let ParsedZone {
            origin,
            records: parsed_records,
            soa,
            count,
            truncated,
        } = parsed;

        state.records = count;
        state.loaded = true;
        if truncated {
            state.error = Some(format!("记录数达到上限 {MAX_ZONE_RECORDS}，已截断"));
        }
        for record in parsed_records {
            records
                .entry(record.owner.clone())
                .or_default()
                .entry(record.rtype)
                .or_default()
                .push(record);
        }
        if let Some(soa) = soa {
            soa_by_origin.insert(origin.clone(), soa);
        }
        origins.push(origin);
        budget = budget.saturating_sub(count);
        states.push(state);
    }

    // Longest suffix first; equal label counts keep configuration order (stable sort).
    origins.sort_by_key(|origin| std::cmp::Reverse(label_count(origin)));

    Compiled {
        enabled: config.enabled,
        default_ttl,
        records,
        soa_by_origin,
        origins,
        states,
    }
}

#[cfg(test)]
mod tests;

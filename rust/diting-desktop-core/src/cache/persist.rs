//! Go-compatible `cache.json` persistence (`cachePersistVersion = 1`).
//!
//! The file shape is part of the upgrade path: an existing Go installation's cache must load in
//! the Rust service, and the Rust writer keeps the same version so a rollback can still read it.
//! A version mismatch discards the whole cache, which is the old behaviour and intentionally safer
//! than guessing what an unknown field means.

use std::path::Path;

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use diting_dns_cache_core::{Cache, PersistEntry};
use serde::{Deserialize, Serialize};

pub const VERSION: i32 = 1;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistFile {
    version: i32,
    saved_at: i64,
    entry_count: usize,
    max_entries: usize,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    config_hash: String,
    entries: Vec<PersistRecord>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PersistRecord {
    key: String,
    domain: String,
    qtype: u16,
    qclass: u16,
    message: String,
    original_ttl: u32,
    expires_at: i64,
    stale_until: i64,
    is_negative: bool,
    rcode: i32,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    ip_list: Vec<String>,
    hit_count: u64,
    last_hit_at: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PersistStatus {
    pub entries: usize,
    pub max_entries: usize,
    pub saved_at: i64,
}

/// Writes the whole cache atomically.
pub fn save(cache: &Cache, path: &Path) -> Result<PersistStatus, String> {
    if path.as_os_str().is_empty() {
        return Err("cache persist: empty path".to_string());
    }
    let exported = cache.export();
    let entries: Vec<PersistRecord> = exported
        .into_iter()
        .map(|entry| PersistRecord {
            key: String::from_utf8_lossy(&entry.key).into_owned(),
            domain: domain_text(&entry.domain),
            qtype: entry.qtype,
            qclass: entry.qclass,
            message: BASE64.encode(&entry.wire),
            original_ttl: entry.original_ttl,
            expires_at: entry.expires_at_ms,
            stale_until: entry.stale_until_ms,
            is_negative: entry.is_negative,
            rcode: response_rcode(&entry.wire).unwrap_or(0),
            ip_list: entry.ip_list,
            hit_count: entry.hit_count,
            last_hit_at: entry.last_hit_at_ms,
        })
        .collect();
    let saved_at = now_ms();
    let payload = PersistFile {
        version: VERSION,
        saved_at,
        entry_count: entries.len(),
        max_entries: cache.capacity(),
        config_hash: String::new(),
        entries,
    };
    let data =
        serde_json::to_vec(&payload).map_err(|error| format!("cache persist: marshal: {error}"))?;
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("cache persist: create dir: {error}"))?;
    }
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, &data).map_err(|error| format!("cache persist: write temp: {error}"))?;
    let _ = std::fs::remove_file(path);
    std::fs::rename(&tmp, path).map_err(|error| format!("cache persist: rename: {error}"))?;
    Ok(PersistStatus {
        entries: payload.entry_count,
        max_entries: payload.max_entries,
        saved_at,
    })
}

/// Loads a cache file. A missing file is not an error (`Ok(0)`), matching the Go startup path.
pub fn load(cache: &Cache, path: &Path) -> Result<usize, String> {
    if path.as_os_str().is_empty() {
        return Err("cache load: empty path".to_string());
    }
    let data = match std::fs::read(path) {
        Ok(data) => data,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(format!("cache load: read: {error}")),
    };
    let payload: PersistFile =
        serde_json::from_slice(&data).map_err(|error| format!("cache load: unmarshal: {error}"))?;
    if payload.version != VERSION {
        return Err(format!(
            "cache load: unsupported version {} (want {VERSION})",
            payload.version
        ));
    }
    let mut entries = Vec::with_capacity(payload.entries.len());
    for record in payload.entries {
        let wire = match BASE64.decode(record.message.as_bytes()) {
            Ok(wire) => wire,
            Err(_) => continue,
        };
        let Some(meta) = diting_dns_wire::parse_response(&wire) else {
            continue;
        };
        let ttl_offsets = if meta.answer_count == 0 {
            meta.authority_ttl_offsets.clone()
        } else {
            meta.answer_ttl_offsets.clone()
        };
        entries.push(PersistEntry {
            key: record.key.into_bytes(),
            domain: record
                .domain
                .trim_end_matches('.')
                .to_ascii_lowercase()
                .into_bytes(),
            qtype: record.qtype,
            qclass: record.qclass,
            wire,
            ttl_offsets,
            original_ttl: record.original_ttl,
            created_at_ms: record.last_hit_at,
            expires_at_ms: record.expires_at,
            stale_until_ms: record.stale_until,
            is_negative: record.is_negative,
            chain_targets: meta.chain_targets,
            ip_list: record.ip_list,
            resolved_ips: meta.resolved_ips,
            hit_count: record.hit_count,
            last_hit_at_ms: record.last_hit_at,
        });
    }
    Ok(cache.import(entries))
}

fn domain_text(bytes: &[u8]) -> String {
    let name = String::from_utf8_lossy(bytes);
    if name.is_empty() {
        name.into_owned()
    } else {
        format!("{}.", name.trim_end_matches('.'))
    }
}

fn response_rcode(wire: &[u8]) -> Option<i32> {
    diting_dns_wire::parse_response(wire).map(|meta| i32::from(meta.rcode))
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_cache_core::policy::{Config, TtlMode};
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord};

    fn response(domain: &str) -> Vec<u8> {
        let query = MessageBuilder::query(domain, 1, 1).finish().unwrap();
        let builder = MessageBuilder::reply_to(&query)
            .unwrap()
            .set_authoritative(true)
            .push_answer(ResourceRecord::new(
                domain,
                1,
                1,
                60,
                RData::A(std::net::Ipv4Addr::new(1, 2, 3, 4)),
            ));
        builder.finish().unwrap()
    }

    #[test]
    fn round_trip() {
        let config = Config {
            enabled: true,
            mode: TtlMode::LimitMaxTtl,
            ..Config::default()
        };
        let cache = Cache::new(config);
        let query = MessageBuilder::query("example.com", 1, 1).finish().unwrap();
        assert!(cache.put(&query, &response("example.com")));
        let dir = std::env::temp_dir().join(format!("diting-cache-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("cache.json");
        let status = save(&cache, &path).unwrap();
        assert_eq!(status.entries, 1);
        cache.clear();
        assert_eq!(load(&cache, &path).unwrap(), 1);
        assert!(cache.get(&query, true).is_some());
        let _ = std::fs::remove_dir_all(&dir);
    }
}

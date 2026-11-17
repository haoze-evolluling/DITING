//! Query-log value types.
//!
//! These mirror `desktop/service/internal/querylog/types.go` exactly: the serde field names match
//! the Go JSON tags (`clientIP`, `durationMs`, …) and the `omitempty` rules are reproduced so the
//! JSON-Lines files and IPC payloads stay interchangeable.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// Normal allowed query.
pub const STATUS_ALLOWED: &str = "allowed";
/// Blocked by the rule engine / access control / rate limiting / rebinding guard.
pub const STATUS_BLOCKED: &str = "blocked";
/// Served from a fresh cache entry.
pub const STATUS_CACHED: &str = "cached";
/// Served from a stale (optimistically reused) cache entry.
pub const STATUS_STALE: &str = "stale";
/// Upstream failure or pipeline error.
pub const STATUS_ERROR: &str = "error";

/// Default in-memory ring capacity.
pub const DEFAULT_MAX_ENTRIES: i32 = 10_000;
/// Default on-disk retention in days.
pub const DEFAULT_RETENTION_DAYS: i32 = 7;
/// Maximum entries returned by a single search.
pub const MAX_SEARCH_LIMIT: i32 = 500;
/// Upper bound accepted by [`Config::normalize`].
pub const MAX_ENTRIES_CAP: i32 = 200_000;
/// Upper retention bound accepted by [`Config::normalize`].
pub const RETENTION_DAYS_CAP: i32 = 365;

/// A single query-history record (one JSON line when persisted).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Record {
    /// Unix milliseconds.
    #[serde(rename = "ts", default)]
    pub timestamp: i64,
    /// Queried domain (with trailing dot).
    #[serde(default)]
    pub domain: String,
    /// Record type, e.g. `A` / `AAAA`.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub qtype: String,
    /// Client IP (blanked when client logging is disabled).
    #[serde(rename = "clientIP", default, skip_serializing_if = "String::is_empty")]
    pub client_ip: String,
    /// Client hostname / alias.
    #[serde(
        rename = "clientName",
        default,
        skip_serializing_if = "String::is_empty"
    )]
    pub client_name: String,
    /// Resolution latency in milliseconds. Always serialized, even when zero.
    #[serde(rename = "durationMs", default)]
    pub duration_ms: f64,
    /// Response code, e.g. `NOERROR` / `NXDOMAIN`.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub rcode: String,
    /// See the `STATUS_*` constants.
    #[serde(default)]
    pub status: String,
    /// Whether the answer came from cache.
    #[serde(default, skip_serializing_if = "is_false")]
    pub cached: bool,
    /// `"fresh"` or `"stale"`.
    #[serde(rename = "cacheHit", default, skip_serializing_if = "String::is_empty")]
    pub cache_hit: String,
    /// Whether the query was blocked.
    #[serde(default, skip_serializing_if = "is_false")]
    pub blocked: bool,
    /// Matched rule text.
    #[serde(
        rename = "filterRule",
        default,
        skip_serializing_if = "String::is_empty"
    )]
    pub filter_rule: String,
    /// Block/allow reason description.
    #[serde(
        rename = "filterReason",
        default,
        skip_serializing_if = "String::is_empty"
    )]
    pub filter_reason: String,
    /// `udp` or `tcp`.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub protocol: String,
    /// Error message.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub error: String,
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// Fold any status string into the controlled enum, falling back to `allowed`.
pub fn normalize_status(status: &str) -> &'static str {
    let trimmed = status.trim();
    if trimmed.eq_ignore_ascii_case(STATUS_BLOCKED) {
        STATUS_BLOCKED
    } else if trimmed.eq_ignore_ascii_case(STATUS_CACHED) {
        STATUS_CACHED
    } else if trimmed.eq_ignore_ascii_case(STATUS_STALE) {
        STATUS_STALE
    } else if trimmed.eq_ignore_ascii_case(STATUS_ERROR) {
        STATUS_ERROR
    } else {
        STATUS_ALLOWED
    }
}

/// Query-history and statistics configuration (Go `QueryLogConfig`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Config {
    /// Master switch: when off nothing is recorded.
    pub enabled: bool,
    /// In-memory ring capacity.
    pub max_entries: i32,
    /// Persist history as JSON-Lines.
    pub file_enabled: bool,
    /// On-disk retention in days.
    pub retention_days: i32,
    /// Whether client IP / hostname are recorded (privacy switch).
    pub log_clients: bool,
    /// Persistence directory.
    pub data_dir: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            enabled: true,
            max_entries: DEFAULT_MAX_ENTRIES,
            file_enabled: true,
            retention_days: DEFAULT_RETENTION_DAYS,
            log_clients: true,
            data_dir: default_querylog_dir().to_string_lossy().into_owned(),
        }
    }
}

impl Config {
    /// Repair defaults and out-of-range values.
    ///
    /// `default_data_dir` is substituted when `data_dir` is blank; callers pass the platform
    /// query-log directory (the Go code used `platform.DefaultQueryLogDir` directly).
    pub fn normalize(&mut self, default_data_dir: impl AsRef<Path>) {
        if self.max_entries <= 0 {
            self.max_entries = DEFAULT_MAX_ENTRIES;
        }
        if self.max_entries > MAX_ENTRIES_CAP {
            self.max_entries = MAX_ENTRIES_CAP;
        }
        if self.retention_days <= 0 {
            self.retention_days = DEFAULT_RETENTION_DAYS;
        }
        if self.retention_days > RETENTION_DAYS_CAP {
            self.retention_days = RETENTION_DAYS_CAP;
        }
        if self.data_dir.trim().is_empty() {
            self.data_dir = default_data_dir.as_ref().to_string_lossy().into_owned();
        }
    }
}

/// A Top-N ranking entry (domain / client plus count).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct NameCount {
    pub name: String,
    pub count: i64,
}

/// One hour of aggregate data (ascending trend point).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HourPoint {
    /// Start of the hour in Unix milliseconds.
    pub hour_ms: i64,
    pub queries: i64,
    pub blocked: i64,
    pub cached: i64,
}

/// Summary over the rolling 24-hour window.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub queries: i64,
    pub blocked: i64,
    pub cached: i64,
    pub forwarded: i64,
    pub errors: i64,
    pub avg_response_ms: f64,
    /// 0 – 1.
    pub cache_hit_rate: f64,
}

/// Query-history search conditions.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SearchQuery {
    pub domain: String,
    pub client: String,
    pub qtype: String,
    pub rcode: String,
    /// `"" | allowed | blocked | cached | stale | error`.
    pub status: String,
    pub start_ms: i64,
    pub end_ms: i64,
    pub limit: i64,
    pub offset: i64,
    /// Fall back to scanning persisted files when memory does not cover the requested page.
    pub include_file: bool,
}

impl SearchQuery {
    /// Whether a record satisfies every supplied condition.
    ///
    /// Domain and client are case-insensitive substrings; qtype/rcode are case-insensitive exact
    /// matches; status is normalized before comparison. Zero time bounds mean "unbounded".
    pub fn matches(&self, record: &Record) -> bool {
        if !self.domain.is_empty()
            && !record
                .domain
                .to_lowercase()
                .contains(&self.domain.to_lowercase())
        {
            return false;
        }
        if !self.client.is_empty() {
            let needle = self.client.to_lowercase();
            if !record.client_ip.to_lowercase().contains(&needle)
                && !record.client_name.to_lowercase().contains(&needle)
            {
                return false;
            }
        }
        if !self.qtype.is_empty() && !record.qtype.eq_ignore_ascii_case(&self.qtype) {
            return false;
        }
        if !self.rcode.is_empty() && !record.rcode.eq_ignore_ascii_case(&self.rcode) {
            return false;
        }
        if !self.status.is_empty()
            && normalize_status(&record.status) != normalize_status(&self.status)
        {
            return false;
        }
        if self.start_ms > 0 && record.timestamp < self.start_ms {
            return false;
        }
        if self.end_ms > 0 && record.timestamp > self.end_ms {
            return false;
        }
        true
    }
}

/// Query-history search result.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct SearchResult {
    pub total: i64,
    pub entries: Vec<Record>,
}

/// The platform query-log directory (`platform.DefaultQueryLogDir`).
pub fn default_querylog_dir() -> PathBuf {
    default_data_dir().join("querylog")
}

/// The mutable data root (`platform.DefaultDataDir`).
pub fn default_data_dir() -> PathBuf {
    if let Some(custom) = std::env::var_os("DITING_DATA_DIR").filter(|v| !v.is_empty()) {
        return PathBuf::from(custom).join("DITING");
    }
    #[cfg(windows)]
    {
        std::env::var_os("ProgramData")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"))
            .join("DITING")
    }
    #[cfg(unix)]
    {
        // Mirror the platform crate: root uses the FHS path, otherwise `~/.diting`.
        match std::env::var_os("HOME").filter(|v| !v.is_empty()) {
            Some(home) => PathBuf::from(home).join(".diting"),
            None => PathBuf::from("/var/lib/diting"),
        }
    }
    #[cfg(not(any(windows, unix)))]
    {
        PathBuf::from(".")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};

    #[test]
    fn json_field_names_and_omitempty() {
        let record = Record {
            timestamp: 1_700_000_000_000,
            domain: "a.com.".into(),
            duration_ms: 12.5,
            status: STATUS_ALLOWED.into(),
            ..Record::default()
        };
        let value: Value = serde_json::to_value(&record).expect("serialize");
        let object = value.as_object().expect("object");
        assert_eq!(object["ts"], json!(1_700_000_000_000i64));
        assert_eq!(object["domain"], json!("a.com."));
        assert_eq!(object["durationMs"], json!(12.5));
        assert_eq!(object["status"], json!("allowed"));
        for omitted in [
            "qtype",
            "clientIP",
            "clientName",
            "rcode",
            "cached",
            "cacheHit",
            "blocked",
            "filterRule",
            "filterReason",
            "protocol",
            "error",
        ] {
            assert!(!object.contains_key(omitted), "{omitted} should be omitted");
        }
    }

    #[test]
    fn json_always_serializes_duration_ms() {
        let value = serde_json::to_value(Record {
            status: STATUS_ALLOWED.into(),
            ..Record::default()
        })
        .expect("serialize");
        assert!(value.get("durationMs").is_some());
    }

    #[test]
    fn json_all_fields_present_round_trip() {
        let record = Record {
            timestamp: 1,
            domain: "a.com.".into(),
            qtype: "A".into(),
            client_ip: "10.0.0.1".into(),
            client_name: "laptop".into(),
            duration_ms: 1.0,
            rcode: "NOERROR".into(),
            status: STATUS_BLOCKED.into(),
            cached: true,
            cache_hit: "fresh".into(),
            blocked: true,
            filter_rule: "||a.com^".into(),
            filter_reason: "rule".into(),
            protocol: "udp".into(),
            error: "boom".into(),
        };
        let encoded = serde_json::to_string(&record).expect("serialize");
        for key in [
            "clientIP",
            "clientName",
            "cacheHit",
            "filterRule",
            "filterReason",
        ] {
            assert!(encoded.contains(key), "missing {key}: {encoded}");
        }
        let decoded: Record = serde_json::from_str(&encoded).expect("deserialize");
        assert_eq!(decoded, record);
    }

    #[test]
    fn json_deserialize_missing_optionals() {
        let record: Record =
            serde_json::from_str(r#"{"ts":5,"domain":"x.com","durationMs":3,"status":"cached"}"#)
                .expect("deserialize");
        assert_eq!(record.timestamp, 5);
        assert_eq!(record.duration_ms, 3.0);
        assert!(record.qtype.is_empty());
        assert!(record.client_ip.is_empty());
        assert!(!record.blocked);
    }

    #[test]
    fn status_normalization() {
        assert_eq!(normalize_status(" BLOCKED "), STATUS_BLOCKED);
        assert_eq!(normalize_status("Cached"), STATUS_CACHED);
        assert_eq!(normalize_status("stale"), STATUS_STALE);
        assert_eq!(normalize_status("error"), STATUS_ERROR);
        assert_eq!(normalize_status("weird"), STATUS_ALLOWED);
        assert_eq!(normalize_status(""), STATUS_ALLOWED);
    }

    #[test]
    fn config_normalize_defaults_and_caps() {
        let mut cfg = Config {
            max_entries: 0,
            retention_days: 0,
            data_dir: "  ".into(),
            ..Config::default()
        };
        cfg.normalize("/tmp/querylog");
        assert_eq!(cfg.max_entries, DEFAULT_MAX_ENTRIES);
        assert_eq!(cfg.retention_days, DEFAULT_RETENTION_DAYS);
        assert_eq!(cfg.data_dir, "/tmp/querylog");

        let mut cfg = Config {
            max_entries: 900_000,
            retention_days: 9_000,
            ..Config::default()
        };
        cfg.normalize("/tmp/querylog");
        assert_eq!(cfg.max_entries, MAX_ENTRIES_CAP);
        assert_eq!(cfg.retention_days, RETENTION_DAYS_CAP);
    }

    #[test]
    fn search_matches_each_filter() {
        let record = Record {
            timestamp: 2_000,
            domain: "Ads.Example.COM.".into(),
            qtype: "AAAA".into(),
            client_ip: "192.168.1.9".into(),
            client_name: "Laptop".into(),
            rcode: "NXDOMAIN".into(),
            status: STATUS_BLOCKED.into(),
            blocked: true,
            ..Record::default()
        };

        assert!(SearchQuery::default().matches(&record));
        assert!(SearchQuery {
            domain: "example".into(),
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(SearchQuery {
            client: "laptop".into(),
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(SearchQuery {
            qtype: "aaaa".into(),
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(SearchQuery {
            rcode: "nxdomain".into(),
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(SearchQuery {
            status: STATUS_BLOCKED.into(),
            start_ms: 2_000,
            end_ms: 2_000,
            ..SearchQuery::default()
        }
        .matches(&record));

        assert!(!SearchQuery {
            domain: "nope".into(),
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(!SearchQuery {
            status: STATUS_ALLOWED.into(),
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(!SearchQuery {
            start_ms: 2_001,
            ..SearchQuery::default()
        }
        .matches(&record));
        assert!(!SearchQuery {
            end_ms: 1_999,
            ..SearchQuery::default()
        }
        .matches(&record));
    }
}

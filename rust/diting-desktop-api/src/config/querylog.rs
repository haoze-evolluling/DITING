//! Query history and statistics configuration.

use serde::{Deserialize, Serialize};

use super::paths::default_query_log_dir;

/// Default in-memory ring buffer size.
pub const DEFAULT_MAX_ENTRIES: i32 = 10_000;
/// Default on-disk retention.
pub const DEFAULT_RETENTION_DAYS: i32 = 7;

const MAX_ENTRIES_LIMIT: i32 = 200_000;
const MAX_RETENTION_DAYS: i32 = 365;

/// Query log configuration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct QueryLogConfig {
    pub enabled: bool,
    pub max_entries: i32,
    pub file_enabled: bool,
    pub retention_days: i32,
    pub log_clients: bool,
    pub data_dir: String,
}

impl Default for QueryLogConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            max_entries: DEFAULT_MAX_ENTRIES,
            file_enabled: true,
            retention_days: DEFAULT_RETENTION_DAYS,
            log_clients: true,
            data_dir: default_query_log_dir().to_string_lossy().into_owned(),
        }
    }
}

impl QueryLogConfig {
    /// Mirror `NormalizeQueryLogConfig`.
    pub fn normalize(&mut self) {
        if self.max_entries <= 0 {
            self.max_entries = DEFAULT_MAX_ENTRIES;
        }
        if self.max_entries > MAX_ENTRIES_LIMIT {
            self.max_entries = MAX_ENTRIES_LIMIT;
        }
        if self.retention_days <= 0 {
            self.retention_days = DEFAULT_RETENTION_DAYS;
        }
        if self.retention_days > MAX_RETENTION_DAYS {
            self.retention_days = MAX_RETENTION_DAYS;
        }
        if self.data_dir.trim().is_empty() {
            self.data_dir = default_query_log_dir().to_string_lossy().into_owned();
        }
    }
}

pub const DEFAULT_LOG_RETENTION_DAYS: i32 = 7;
pub const MAX_LOG_RETENTION_DAYS: i32 = 30;
pub const DEFAULT_TRAFFIC_RETENTION_DAYS: i32 = 30;
pub const MAX_TRAFFIC_RETENTION_DAYS: i32 = 90;
pub const DAY_MS: i64 = 24 * 60 * 60 * 1000;

pub const BATCH_ROWS: i64 = 5_000;

pub const PRUNED_TABLES: [&str; 4] = [
    "dns_log",
    "http_request_log",
    "dns_race_log",
    "bootstrap_log",
];

pub const TRAFFIC_TABLE: &str = "app_traffic_daily";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StoredDays {
    pub present: bool,
    pub value: i32,
}

impl StoredDays {
    pub fn present(value: i32) -> Self {
        Self {
            present: true,
            value,
        }
    }

    pub fn absent() -> Self {
        Self {
            present: false,
            value: 0,
        }
    }

    fn resolve(self, default: i32, maximum: i32) -> i32 {
        let raw = if self.present { self.value } else { default };
        raw.clamp(1, maximum)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Plan {
    pub log_days: i32,
    pub log_cutoff_ms: i64,
    pub traffic_days: i32,
    pub traffic_cutoff_ms: i64,
}

pub fn plan(log_days: StoredDays, traffic_days: StoredDays, now_ms: i64) -> Plan {
    let log_days = log_days.resolve(DEFAULT_LOG_RETENTION_DAYS, MAX_LOG_RETENTION_DAYS);
    let traffic_days =
        traffic_days.resolve(DEFAULT_TRAFFIC_RETENTION_DAYS, MAX_TRAFFIC_RETENTION_DAYS);
    Plan {
        log_days,
        log_cutoff_ms: now_ms - log_days as i64 * DAY_MS,
        traffic_days,
        traffic_cutoff_ms: now_ms - traffic_days as i64 * DAY_MS,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_700_000_000_000;

    #[test]
    fn missing_settings_take_the_defaults() {
        let planned = plan(StoredDays::absent(), StoredDays::absent(), NOW);
        assert_eq!(planned.log_days, DEFAULT_LOG_RETENTION_DAYS);
        assert_eq!(planned.traffic_days, DEFAULT_TRAFFIC_RETENTION_DAYS);
        assert_eq!(planned.log_cutoff_ms, NOW - 7 * DAY_MS);
        assert_eq!(planned.traffic_cutoff_ms, NOW - 30 * DAY_MS);
    }

    #[test]
    fn stored_windows_are_clamped_into_range() {
        assert_eq!(
            plan(StoredDays::present(0), StoredDays::present(0), NOW).log_days,
            1
        );
        assert_eq!(
            plan(StoredDays::present(-3), StoredDays::present(-3), NOW).traffic_days,
            1
        );
        assert_eq!(
            plan(StoredDays::present(90), StoredDays::present(90), NOW).log_days,
            30
        );
        assert_eq!(
            plan(StoredDays::present(1000), StoredDays::present(1000), NOW).traffic_days,
            90
        );
        assert_eq!(
            plan(StoredDays::present(14), StoredDays::present(60), NOW).log_days,
            14
        );
    }

    #[test]
    fn the_tables_and_the_batch_size_are_the_old_ones() {
        assert_eq!(
            PRUNED_TABLES,
            [
                "dns_log",
                "http_request_log",
                "dns_race_log",
                "bootstrap_log"
            ]
        );
        assert_eq!(TRAFFIC_TABLE, "app_traffic_daily");
        assert_eq!(BATCH_ROWS, 5_000);
    }
}

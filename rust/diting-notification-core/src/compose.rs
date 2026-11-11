//! The optional detail line under the running-text status.

use std::collections::HashMap;

use serde_json::Value;

/// Request counters copied out of the log kernel for one rendering.
#[derive(Clone, Copy, Default)]
pub struct Stats {
    pub total: i64,
    pub passed: i64,
    pub filtered: i64,
    pub failed: i64,
    pub cached: i64,
    pub rewritten: i64,
}

const FALLBACK_LABELS: [(&str, &str); 6] = [
    ("total", "请求"),
    ("passed", "通过"),
    ("filtered", "过滤"),
    ("failed", "失败"),
    ("cached", "缓存命中"),
    ("rewritten", "覆写"),
];

/// Null when nothing is enabled, so the caller keeps the body to the status text alone.
/// `with_speed` is false where no traffic monitor runs (express and server modes).
pub fn compose(
    items: &str,
    labels_json: &str,
    stats: &Stats,
    with_speed: bool,
    tx_bps: i64,
    rx_bps: i64,
) -> Option<String> {
    let labels = labels(labels_json);
    let mut parts: Vec<String> = Vec::new();
    for id in items.split('\n').map(str::trim).filter(|id| !id.is_empty()) {
        let value = match id {
            "total" => stats.total,
            "passed" => stats.passed,
            "filtered" => stats.filtered,
            "failed" => stats.failed,
            "cached" => stats.cached,
            "rewritten" => stats.rewritten,
            "speed" => {
                if with_speed {
                    parts.push(format_rates(tx_bps, rx_bps));
                }
                continue;
            }
            _ => continue,
        };
        let label = labels
            .get(id)
            .map(String::as_str)
            .filter(|text| !text.trim().is_empty())
            .or_else(|| fallback_label(id))
            .unwrap_or(id);
        parts.push(format!("{label} {}", format_number(value)));
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join("  ·  "))
    }
}

/// `1234567` → `1,234,567`, matching `NumberFormat.getIntegerInstance(Locale.US)`.
pub fn format_number(value: i64) -> String {
    let digits = value.unsigned_abs().to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3 + 1);
    if value < 0 {
        out.push('-');
    }
    for (index, digit) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            out.push(',');
        }
        out.push(digit);
    }
    out
}

/// `↑ 1.5 MB/s  ↓ 512 KB/s`: 1024-based, one decimal for MB, none for KB.
pub fn format_rates(tx_bps: i64, rx_bps: i64) -> String {
    format!("↑ {}  ↓ {}", format_rate(tx_bps), format_rate(rx_bps))
}

fn format_rate(bytes: i64) -> String {
    const KB: i64 = 1024;
    const MB: i64 = 1024 * 1024;
    if bytes >= MB {
        let tenths = ((bytes as f64 / MB as f64) * 10.0).round() as i64;
        format!("{}.{} MB/s", tenths / 10, tenths % 10)
    } else if bytes >= KB {
        format!("{} KB/s", (bytes as f64 / KB as f64).round() as i64)
    } else {
        format!("{bytes} B/s")
    }
}

fn labels(raw: &str) -> HashMap<String, String> {
    let parsed: Value = serde_json::from_str(raw).unwrap_or(Value::Null);
    let Value::Object(object) = parsed else {
        return HashMap::new();
    };
    object
        .into_iter()
        .map(|(key, value)| {
            let text = match value {
                Value::String(text) => text,
                Value::Null => String::new(),
                other => other.to_string(),
            };
            (key, text)
        })
        .filter(|(_, text)| !text.trim().is_empty())
        .collect()
}

fn fallback_label(id: &str) -> Option<&'static str> {
    FALLBACK_LABELS
        .iter()
        .find_map(|(key, label)| (*key == id).then_some(*label))
}

#[cfg(test)]
mod tests {
    use super::{compose, format_number, format_rates, Stats};

    fn stats() -> Stats {
        Stats {
            total: 1_234,
            passed: 7,
            filtered: 3,
            failed: 1,
            cached: 2,
            rewritten: 4,
        }
    }

    #[test]
    fn numbers_use_us_grouping() {
        assert_eq!(format_number(0), "0");
        assert_eq!(format_number(12), "12");
        assert_eq!(format_number(123), "123");
        assert_eq!(format_number(1_234), "1,234");
        assert_eq!(format_number(1_234_567), "1,234,567");
        assert_eq!(format_number(-1_234), "-1,234");
    }

    #[test]
    fn rates_match_the_legacy_units() {
        assert_eq!(format_rates(0, 1023), "↑ 0 B/s  ↓ 1023 B/s");
        assert_eq!(format_rates(1024, 1_536), "↑ 1 KB/s  ↓ 2 KB/s");
        assert_eq!(format_rates(1_572_864, 524_288), "↑ 1.5 MB/s  ↓ 512 KB/s");
    }

    #[test]
    fn labels_prefer_the_localized_map_then_the_fallback() {
        let line = compose(
            "total\nfailure\nmissing\npassed",
            r#"{"total":"Requests","passed":"  "}"#,
            &stats(),
            true,
            0,
            0,
        );
        assert_eq!(line.as_deref(), Some("Requests 1,234  ·  通过 7"));
    }

    #[test]
    fn speed_is_only_rendered_when_the_mode_has_a_monitor() {
        let on = compose("speed\ntotal", "", &stats(), true, 1_572_864, 0);
        assert_eq!(on.as_deref(), Some("↑ 1.5 MB/s  ↓ 0 B/s  ·  请求 1,234"));
        let off = compose("speed\ntotal", "", &stats(), false, 1_572_864, 0);
        assert_eq!(off.as_deref(), Some("请求 1,234"));
    }

    #[test]
    fn empty_or_unknown_items_produce_no_line() {
        assert_eq!(compose("", "", &stats(), true, 0, 0), None);
        assert_eq!(compose("speed", "", &stats(), false, 1, 1), None);
        assert_eq!(compose("unknown", "", &stats(), true, 0, 0), None);
    }

    #[test]
    fn malformed_labels_fall_back_to_the_built_in_text() {
        let line = compose("cached", "not json", &stats(), false, 0, 0);
        assert_eq!(line.as_deref(), Some("缓存命中 2"));
    }
}

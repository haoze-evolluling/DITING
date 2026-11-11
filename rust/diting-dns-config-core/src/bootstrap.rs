//! `bootstrap_custom_json`: the user's own bootstrap addresses.
//!
//! The row keeps `enabled` because the settings page toggles it, while the document only carries
//! the enabled ones. Ids and names are filled in from the address when blank — that fallback is the
//! reason a row pasted twice does not produce two different rows.

use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BootstrapRow {
    pub id: String,
    pub name: String,
    pub ip: String,
    pub enabled: bool,
}

#[derive(Serialize)]
struct BootstrapRowRecord<'a> {
    id: &'a str,
    name: &'a str,
    ip: &'a str,
    enabled: bool,
}

/// Reads the custom rows; a row without an address, or of the wrong shape, is dropped.
pub fn parse_custom(raw: Option<&str>) -> Vec<BootstrapRow> {
    let Some(raw) = raw else {
        return Vec::new();
    };
    if raw.is_empty() {
        return Vec::new();
    }
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(raw) else {
        return Vec::new();
    };
    let mut rows = Vec::with_capacity(items.len());
    for item in items {
        let Value::Object(record) = item else {
            continue;
        };
        let Some(ip) = record
            .get("ip")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|ip| !ip.is_empty())
        else {
            continue;
        };
        let id = record
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or("");
        let name = record
            .get("name")
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or("");
        rows.push(BootstrapRow {
            id: if id.is_empty() {
                format!("custom_{ip}")
            } else {
                id.to_string()
            },
            name: if name.is_empty() {
                ip.to_string()
            } else {
                name.to_string()
            },
            ip: ip.to_string(),
            enabled: record.get("enabled").and_then(Value::as_bool) != Some(false),
        });
    }
    rows
}

/// Writes the rows back in the four-field shape the settings page edits.
pub fn encode_custom(rows: &[BootstrapRow]) -> String {
    let records: Vec<BootstrapRowRecord<'_>> = rows
        .iter()
        .map(|row| BootstrapRowRecord {
            id: &row.id,
            name: &row.name,
            ip: &row.ip,
            enabled: row.enabled,
        })
        .collect();
    serde_json::to_string(&records).unwrap_or_else(|_| String::from("[]"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blanks_fall_back_to_the_address() {
        let rows = parse_custom(Some(
            r#"[{"id":"","name":"","ip":"9.9.9.9","enabled":true},
                {"id":"c1","name":"自建","ip":" 5.6.7.8 "},
                {"id":"off","name":"关","ip":"1.2.3.4","enabled":false}]"#,
        ));
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].id, "custom_9.9.9.9");
        assert_eq!(rows[0].name, "9.9.9.9");
        assert!(rows[0].enabled);
        assert_eq!(rows[1].ip, "5.6.7.8");
        assert!(rows[1].enabled);
        assert!(!rows[2].enabled);
    }

    #[test]
    fn rows_without_an_address_or_shape_are_dropped() {
        let rows = parse_custom(Some(
            r#"[{"id":"a","name":"A","ip":"   "},{"id":"b","name":"B"},1]"#,
        ));
        assert!(rows.is_empty());
        assert!(parse_custom(None).is_empty());
        assert!(parse_custom(Some("")).is_empty());
        assert!(parse_custom(Some("{}")).is_empty());
    }

    #[test]
    fn encode_round_trips_the_four_fields() {
        let text = encode_custom(&[BootstrapRow {
            id: "custom_9.9.9.9".to_string(),
            name: "9.9.9.9".to_string(),
            ip: "9.9.9.9".to_string(),
            enabled: false,
        }]);
        assert_eq!(
            text,
            r#"[{"id":"custom_9.9.9.9","name":"9.9.9.9","ip":"9.9.9.9","enabled":false}]"#
        );
        assert_eq!(
            parse_custom(Some(&text)),
            [BootstrapRow {
                id: "custom_9.9.9.9".to_string(),
                name: "9.9.9.9".to_string(),
                ip: "9.9.9.9".to_string(),
                enabled: false,
            }]
        );
    }
}

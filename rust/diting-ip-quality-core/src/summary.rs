//! Report aggregation: majority type, the severity tie-break, the level and the first non-empty
//! organization/ASN.

use std::collections::HashMap;

use serde_json::{json, Value};

fn text<'a>(source: &'a Value, key: &str) -> &'a str {
    source.get(key).and_then(Value::as_str).unwrap_or("")
}

fn severity(ip_type: &str) -> i32 {
    match ip_type {
        "机房" => 3,
        "商业" => 2,
        "移动" => 1,
        _ => 0,
    }
}

/// Summarizes the source rows in the order the caller queried them.
pub fn summarize(ip: &str, sources: &[Value]) -> Value {
    let mut counts: HashMap<&str, i32> = HashMap::new();
    for source in sources {
        if text(source, "status") != "命中" {
            continue;
        }
        let ip_type = text(source, "ipType");
        if ip_type.is_empty() {
            continue;
        }
        *counts.entry(ip_type).or_insert(0) += 1;
    }

    // Highest count wins; a tie goes to the more severe type (datacenter > business > mobile).
    let mut ip_type = "商业";
    let mut best = (-1, -1);
    for (candidate, count) in &counts {
        let key = (*count, severity(candidate));
        if key > best {
            best = key;
            ip_type = candidate;
        }
    }

    let level = match ip_type {
        "机房" => "风险",
        "移动" => "优秀",
        _ => "一般",
    };
    let organization = sources
        .iter()
        .filter(|source| text(source, "status") == "命中")
        .map(|source| text(source, "organization"))
        .find(|value| !value.is_empty())
        .unwrap_or("");
    let asn = sources
        .iter()
        .filter(|source| text(source, "status") == "命中")
        .map(|source| text(source, "asn"))
        .find(|value| !value.is_empty())
        .unwrap_or("");

    json!({
        "ip": ip,
        "ipType": ip_type,
        "level": level,
        "organization": organization,
        "asn": asn,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(status: &str, ip_type: &str, organization: &str, asn: &str) -> Value {
        json!({
            "status": status,
            "ipType": ip_type,
            "organization": organization,
            "asn": asn,
        })
    }

    #[test]
    fn majority_type_wins() {
        let report = summarize(
            "1.2.3.4",
            &[
                row("命中", "机房", "", "AS1"),
                row("命中", "机房", "Google", ""),
                row("命中", "移动", "", ""),
            ],
        );
        assert_eq!(report["ipType"], "机房");
        assert_eq!(report["level"], "风险");
        assert_eq!(report["organization"], "Google");
        assert_eq!(report["asn"], "AS1");
    }

    #[test]
    fn ties_break_toward_the_more_severe_type() {
        let report = summarize(
            "1.2.3.4",
            &[row("命中", "移动", "", ""), row("命中", "商业", "", "")],
        );
        assert_eq!(report["ipType"], "商业");
        assert_eq!(report["level"], "一般");
    }

    #[test]
    fn only_hits_count_and_missing_types_fall_back_to_business() {
        let report = summarize(
            "1.2.3.4",
            &[
                row("失败", "移动", "ignored", "AS9"),
                row("命中", "", "", ""),
            ],
        );
        assert_eq!(report["ipType"], "商业");
        assert_eq!(report["level"], "一般");
        assert_eq!(report["organization"], "");
        assert_eq!(report["asn"], "");
    }

    #[test]
    fn mobile_is_excellent() {
        let report = summarize("1.2.3.4", &[row("命中", "移动", "", "")]);
        assert_eq!(report["level"], "优秀");
    }
}

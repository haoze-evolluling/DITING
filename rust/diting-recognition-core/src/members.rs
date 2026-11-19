//! Parses the shipped member list. A wrong root, mistyped field, duplicate entry or bad avatar file
//! name rejects the whole document so the caller keeps the last good cache.

use std::collections::HashSet;

use serde_json::{json, Value};

/// Upper bound for a sponsor's repeat count; a typo or a hostile document cannot turn one row into a
/// four-digit badge.
const MAX_SPONSOR_COUNT: i64 = 9999;

/// Avatar decorations the UI knows how to draw; a closed list, so a typo shows up as a rejected
/// document instead of a silently decorated row.
const AVATAR_FRAMES: [&str; 1] = ["rainbow"];

fn is_avatar_file_name(name: &str) -> bool {
    let Some(stem) = name.strip_suffix("_avatar.jpg") else {
        return false;
    };
    !stem.is_empty()
        && stem
            .chars()
            .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_')
}

fn parse_field(raw: Option<&Value>, field: &str) -> Result<Vec<Value>, String> {
    let Some(items) = raw.and_then(Value::as_array) else {
        return Err(format!("名单配置缺少 {field} 数组"));
    };
    let mut members = Vec::with_capacity(items.len());
    let mut names = HashSet::new();
    let mut avatar_names = HashSet::new();
    for item in items {
        let Some(object) = item.as_object() else {
            return Err(format!("{field} 中存在非对象元素"));
        };
        let Some(name) = object.get("name").and_then(Value::as_str) else {
            return Err(format!("{field} 中存在空的成员名称"));
        };
        let name = name.trim();
        if name.is_empty() {
            return Err(format!("{field} 中存在空的成员名称"));
        }
        if !names.insert(name.to_owned()) {
            return Err(format!("{field} 中存在重复成员：{name}"));
        }
        let avatar = match object.get("avatarFileName") {
            None | Some(Value::Null) => None,
            Some(Value::String(raw_avatar)) => {
                let value = raw_avatar.trim();
                if value.is_empty() {
                    None
                } else {
                    if !is_avatar_file_name(value) {
                        return Err(format!("{field} 中 {name} 的头像文件名无效：{value}"));
                    }
                    if !avatar_names.insert(value.to_owned()) {
                        return Err(format!("{field} 中存在重复头像文件：{value}"));
                    }
                    Some(value.to_owned())
                }
            }
            Some(_) => {
                return Err(format!("{field} 中 {name} 的头像文件名类型错误"));
            }
        };
        let frame = match object.get("frame") {
            None | Some(Value::Null) => None,
            Some(Value::String(raw_frame)) => {
                let value = raw_frame.trim();
                if value.is_empty() {
                    None
                } else {
                    if !AVATAR_FRAMES.contains(&value) {
                        return Err(format!("{field} 中 {name} 的头像框无效：{value}"));
                    }
                    Some(value.to_owned())
                }
            }
            Some(_) => return Err(format!("{field} 中 {name} 的头像框类型错误")),
        };
        // Absent means "sponsored once"; the UI only draws a badge when the value is above one.
        let count = match object.get("count") {
            None | Some(Value::Null) => 1,
            Some(value) => match value.as_i64() {
                Some(count) if (1..=MAX_SPONSOR_COUNT).contains(&count) => count,
                _ => return Err(format!("{field} 中 {name} 的赞助次数无效")),
            },
        };
        members.push(json!({
            "name": name,
            "avatarFileName": avatar,
            "count": count,
            "frame": frame,
        }));
    }
    Ok(members)
}

/// Returns `{ok:true, version, sponsors}` or `{ok:false, error}`.
pub fn parse_members(raw: &str) -> Value {
    let decoded: Value = match serde_json::from_str(raw) {
        Ok(value) => value,
        Err(error) => {
            return json!({ "ok": false, "error": format!("名单配置不是合法 JSON：{error}") });
        }
    };
    let Some(object) = decoded.as_object() else {
        return json!({ "ok": false, "error": "名单配置根节点必须是对象" });
    };
    let Some(version) = object.get("version").and_then(Value::as_i64) else {
        return json!({ "ok": false, "error": "名单配置缺少版本号" });
    };
    let sponsors = match parse_field(object.get("sponsors"), "sponsors") {
        Ok(members) => members,
        Err(error) => return json!({ "ok": false, "error": error }),
    };
    json!({
        "ok": true,
        "version": version,
        "sponsors": sponsors,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_document_trims_and_preserves_order() {
        let answer = parse_members(
            r#"{"version":2,"sponsors":[{"name":" a ","avatarFileName":" a_avatar.jpg "},{"name":"b"}]}"#,
        );
        assert_eq!(answer["ok"], true);
        assert_eq!(answer["version"], 2);
        assert_eq!(answer["sponsors"][0]["name"], "a");
        assert_eq!(answer["sponsors"][0]["avatarFileName"], "a_avatar.jpg");
        assert_eq!(answer["sponsors"][0]["count"], 1);
        assert!(answer["sponsors"][1]["avatarFileName"].is_null());
        assert_eq!(answer["sponsors"][1]["count"], 1);
        assert!(answer["sponsors"][1]["frame"].is_null());
    }

    #[test]
    fn avatar_frame_passes_through_and_is_checked() {
        let answer =
            parse_members(r#"{"version":7,"sponsors":[{"name":"healer","frame":" rainbow "}]}"#);
        assert_eq!(answer["ok"], true);
        assert_eq!(answer["sponsors"][0]["frame"], "rainbow");
        for raw in [
            r#"{"version":1,"sponsors":[{"name":"a","frame":"Rouge"}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","frame":1}]}"#,
        ] {
            assert_eq!(parse_members(raw)["ok"], false, "{raw}");
        }
    }

    #[test]
    fn sponsor_count_passes_through() {
        let answer = parse_members(r#"{"version":3,"sponsors":[{"name":"healer","count":4}]}"#);
        assert_eq!(answer["ok"], true);
        assert_eq!(answer["sponsors"][0]["count"], 4);
    }

    #[test]
    fn invalid_sponsor_count_rejects_the_document() {
        for raw in [
            r#"{"version":1,"sponsors":[{"name":"a","count":0}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","count":-1}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","count":1.5}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","count":"2"}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","count":10000}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","count":true}]}"#,
        ] {
            assert_eq!(parse_members(raw)["ok"], false, "{raw}");
        }
    }

    #[test]
    fn root_version_and_arrays_are_required() {
        for raw in [
            "not json",
            "[]",
            r#"{"sponsors":[]}"#,
            r#"{"version":"1","sponsors":[]}"#,
            r#"{"version":1,"sponsors":{}}"#,
        ] {
            assert_eq!(parse_members(raw)["ok"], false, "{raw}");
        }
    }

    #[test]
    fn bad_entries_reject_the_whole_document() {
        for raw in [
            r#"{"version":1,"sponsors":[{}]}"#,
            r#"{"version":1,"sponsors":[{"name":"  "}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a"},{"name":" a "}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","avatarFileName":1}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","avatarFileName":"A.png"}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a","avatarFileName":"x_avatar.jpg"},{"name":"b","avatarFileName":" x_avatar.jpg "}]}"#,
            r#"{"version":1,"sponsors":[{"name":"a"},1]}"#,
        ] {
            assert_eq!(parse_members(raw)["ok"], false, "{raw}");
        }
    }

    #[test]
    fn avatar_name_pattern_matches_the_dart_regex() {
        assert!(is_avatar_file_name("a_avatar.jpg"));
        assert!(is_avatar_file_name("a_1_avatar.jpg"));
        assert!(!is_avatar_file_name("_avatar.jpg"));
        assert!(!is_avatar_file_name("A_avatar.jpg"));
        assert!(!is_avatar_file_name("a_avatar.JPG"));
        assert!(!is_avatar_file_name("a.png"));
        assert!(!is_avatar_file_name("a_avatar.jpg.tmp"));
    }
}

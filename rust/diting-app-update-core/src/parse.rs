//! The legacy `AppUpdateChecker` rules: trim the tag, drop one leading `v`, compare each dotted
//! segment as an integer, tolerate missing fields but never guess a version or a download URL.

use serde_json::{json, Map, Value};

/// Dart's `'${value ?? ''}'`: strings pass through, scalars use their JSON text, null is empty.
fn text(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(text)) => text.clone(),
        Some(other) => other.to_string(),
    }
}

fn components(value: &str) -> Option<Vec<i64>> {
    let normalized = value.trim();
    let normalized = normalized.strip_prefix('v').unwrap_or(normalized);
    let normalized = normalized.split('-').next().unwrap_or("");
    if normalized.is_empty() {
        return None;
    }
    normalized
        .split('.')
        .map(|part| part.parse::<i64>().ok())
        .collect()
}

/// Component-wise integer comparison; anything unparseable counts as "not newer".
pub fn is_newer_version(remote: &str, current: &str) -> bool {
    let (Some(remote_parts), Some(current_parts)) = (components(remote), components(current))
    else {
        return false;
    };
    let length = remote_parts.len().max(current_parts.len());
    for index in 0..length {
        let remote_value = remote_parts.get(index).copied().unwrap_or(0);
        let current_value = current_parts.get(index).copied().unwrap_or(0);
        if remote_value != current_value {
            return remote_value > current_value;
        }
    }
    false
}

fn is_apk(asset: &Map<String, Value>) -> bool {
    text(asset.get("name")).to_lowercase().ends_with(".apk")
}

fn pick_asset(assets: Option<&Value>) -> Option<&Map<String, Value>> {
    let assets = assets?.as_array()?;
    let maps: Vec<&Map<String, Value>> = assets.iter().filter_map(Value::as_object).collect();
    maps.iter()
        .find(|asset| is_apk(asset) && text(asset.get("name")).to_lowercase().contains("arm64-v8a"))
        .copied()
        .or_else(|| maps.iter().find(|asset| is_apk(asset)).copied())
}

fn error(code: &str) -> Value {
    json!({ "kind": "error", "code": code })
}

/// Parses one `releases/latest` body; `current_version` is echoed for the up-to-date result.
pub fn parse_latest_release(payload: &str, current_version: &str) -> Value {
    let Ok(decoded) = serde_json::from_str::<Value>(payload) else {
        return error("responseNotJson");
    };
    let Some(object) = decoded.as_object() else {
        return error("unexpectedFormat");
    };
    let remote_version = text(object.get("tag_name")).trim().to_owned();
    if remote_version.is_empty() {
        return error("missingTag");
    }
    if !is_newer_version(&remote_version, current_version) {
        return json!({ "kind": "upToDate", "currentVersion": current_version });
    }
    let Some(asset) = pick_asset(object.get("assets")) else {
        return error("noApk");
    };
    let download_url = text(asset.get("browser_download_url")).trim().to_owned();
    if download_url.is_empty() {
        return error("badDownloadUrl");
    }
    let name = text(asset.get("name")).trim().to_owned();
    let version = remote_version
        .strip_prefix('v')
        .unwrap_or(&remote_version)
        .to_owned();
    json!({
        "kind": "available",
        "currentVersion": current_version,
        "version": version,
        "downloadUrl": download_url,
        "fileName": if name.is_empty() { Value::Null } else { Value::String(name) },
        "releaseNotes": text(object.get("body")).trim(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integer_comparison_and_missing_segments() {
        assert!(is_newer_version("1.4.10", "1.4.9"));
        assert!(!is_newer_version("1.4.9", "1.4.10"));
        assert!(is_newer_version("1.5", "1.4.4"));
        assert!(is_newer_version("1.4.4.1", "1.4.4"));
        assert!(!is_newer_version("1.4", "1.4.0"));
        assert!(!is_newer_version("latest", "1.4.4"));
        assert!(!is_newer_version("1.4.x", "1.4.4"));
        assert!(!is_newer_version("", "1.4.4"));
        assert!(is_newer_version("v1.4.5", "1.4.4"));
        assert!(is_newer_version("1.4.5-beta", "1.4.4"));
    }

    #[test]
    fn parse_available_strips_one_v_and_keeps_notes() {
        let answer = parse_latest_release(
            r#"{"tag_name":"v1.4.5","body":"- fix","assets":[{"name":"DITING-arm64-v8a.apk","browser_download_url":"https://x/a.apk"}]}"#,
            "1.4.4",
        );
        assert_eq!(answer["kind"], "available");
        assert_eq!(answer["version"], "1.4.5");
        assert_eq!(answer["fileName"], "DITING-arm64-v8a.apk");
        assert_eq!(answer["downloadUrl"], "https://x/a.apk");
        assert_eq!(answer["releaseNotes"], "- fix");
    }

    #[test]
    fn blank_asset_name_is_not_an_apk() {
        let answer = parse_latest_release(
            r#"{"tag_name":"v2.0.0","assets":[{"name":"  ","browser_download_url":" https://x/u.apk "}]}"#,
            "1.0.0",
        );
        assert_eq!(answer["kind"], "error");
        assert_eq!(answer["code"], "noApk");
    }

    #[test]
    fn asset_preference_and_fallbacks() {
        let answer = parse_latest_release(
            r#"{"tag_name":"v2.0.0","assets":[{"name":"universal.apk","browser_download_url":"https://x/u.apk"},{"name":"arm64-v8a.apk","browser_download_url":"https://x/a.apk"}]}"#,
            "1.0.0",
        );
        assert_eq!(answer["downloadUrl"], "https://x/a.apk");
        let fallback = parse_latest_release(
            r#"{"tag_name":"v2.0.0","assets":[{"name":"notes.txt","browser_download_url":"https://x/n.txt"},{"name":"universal.APK","browser_download_url":"https://x/u.apk"}]}"#,
            "1.0.0",
        );
        assert_eq!(fallback["downloadUrl"], "https://x/u.apk");
    }

    #[test]
    fn explicit_errors() {
        assert_eq!(
            parse_latest_release("not json", "1.0.0")["code"],
            "responseNotJson"
        );
        assert_eq!(
            parse_latest_release("[]", "1.0.0")["code"],
            "unexpectedFormat"
        );
        assert_eq!(
            parse_latest_release(r#"{"assets":[]}"#, "1.0.0")["code"],
            "missingTag"
        );
        assert_eq!(
            parse_latest_release(
                r#"{"tag_name":"v2.0.0","assets":[{"name":"x.zip","browser_download_url":"https://x/s.zip"}]}"#,
                "1.0.0"
            )["code"],
            "noApk"
        );
        assert_eq!(
            parse_latest_release(
                r#"{"tag_name":"v2.0.0","assets":[{"name":"x.apk","browser_download_url":"  "}]}"#,
                "1.0.0"
            )["code"],
            "badDownloadUrl"
        );
    }

    #[test]
    fn same_or_older_is_up_to_date() {
        let same = parse_latest_release(r#"{"tag_name":"v1.4.4"}"#, "1.4.4");
        assert_eq!(same["kind"], "upToDate");
        assert_eq!(same["currentVersion"], "1.4.4");
        let older = parse_latest_release(r#"{"tag_name":"v1.4.3"}"#, "1.4.4");
        assert_eq!(older["kind"], "upToDate");
    }
}

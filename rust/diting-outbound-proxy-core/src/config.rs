//! App-facing outbound-proxy configuration.
//!
//! The engine rules are imported from `diting-proxy-core::config`; this file only adds the three
//! things the Flutter/Kotlin side knows and the engine does not: the proxy app package, the
//! installed-package set and the per-app target list. Validation keeps the legacy order so the
//! first offending field is still the one the UI points at.

use diting_proxy_core::config::{
    normalize_host, normalize_protocol, normalize_scope, valid_credentials, valid_port, SCOPE_APPS,
};
use serde_json::Value;

/// One decoded app configuration; status fields are storage/UI state and do not matter here.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AppConfig {
    pub enabled: bool,
    pub protocol: String,
    pub host: String,
    pub port: i64,
    pub username: String,
    pub password: String,
    pub proxy_app_package: String,
    pub scope: String,
    pub target_packages: Vec<String>,
}

impl AppConfig {
    /// Reads the Dart map; defaults are the legacy form defaults.
    pub fn from_value(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let text = |key: &str, fallback: &str| {
            object
                .get(key)
                .and_then(Value::as_str)
                .unwrap_or(fallback)
                .to_owned()
        };
        Some(Self {
            enabled: object
                .get("enabled")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            protocol: text("protocol", "socks5"),
            host: text("host", "127.0.0.1"),
            port: object.get("port").and_then(Value::as_i64).unwrap_or(7890),
            username: text("username", ""),
            password: text("password", ""),
            proxy_app_package: text("proxyAppPackage", ""),
            scope: text("scope", "all"),
            target_packages: object
                .get("targetPackages")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
        })
    }

    /// Targets that would actually be proxied: blank names and the proxy app itself are dropped,
    /// duplicates are removed, and the result is sorted for the engine JSON.
    pub fn effective_targets(&self) -> Vec<String> {
        let mut targets: Vec<String> = Vec::new();
        for package in &self.target_packages {
            if package.is_empty() || package == &self.proxy_app_package || targets.contains(package)
            {
                continue;
            }
            targets.push(package.clone());
        }
        targets.sort();
        targets
    }

    /// The first rejected field as a stable token; the Dart caller owns the localized sentence.
    /// The order matches the legacy `validationError`: host, port, app presence, self, installed,
    /// credentials, per-app targets.
    pub fn validation_error(
        &self,
        self_package: Option<&str>,
        installed_packages: Option<&[String]>,
    ) -> Option<&'static str> {
        if normalize_host(&self.host).is_none() {
            return Some("host");
        }
        if !valid_port(self.port) {
            return Some("port");
        }
        if self.proxy_app_package.trim().is_empty() {
            return Some("proxyAppRequired");
        }
        if self_package == Some(self.proxy_app_package.as_str()) {
            return Some("proxyAppSelf");
        }
        if let Some(installed) = installed_packages {
            if !installed
                .iter()
                .any(|package| package == &self.proxy_app_package)
            {
                return Some("proxyAppMissing");
            }
        }
        if !valid_credentials(&self.username, &self.password) {
            return Some("credentials");
        }
        if normalize_scope(&self.scope) == SCOPE_APPS && self.effective_targets().is_empty() {
            return Some("targets");
        }
        None
    }

    /// The exact JSON `Engine.configureOutboundProxy` decodes. The key order is the legacy one and
    /// `port` stays a number, because a string would leave the Go struct's `Port` zero.
    pub fn engine_json(&self) -> String {
        let protocol = normalize_protocol(&self.protocol).unwrap_or("socks5");
        let mut parts = vec![
            format!("\"enabled\":{}", self.enabled),
            format!("\"protocol\":\"{protocol}\""),
            format!("\"host\":\"{}\"", escape(&self.host)),
            format!("\"port\":{}", self.port),
            format!("\"username\":\"{}\"", escape(&self.username)),
            format!("\"password\":\"{}\"", escape(&self.password)),
        ];
        if normalize_scope(&self.scope) == SCOPE_APPS {
            let packages: Vec<String> = self
                .effective_targets()
                .iter()
                .map(|package| format!("\"{}\"", escape(package)))
                .collect();
            parts.push("\"scope\":\"apps\"".to_string());
            parts.push(format!("\"packages\":[{}]", packages.join(",")));
        }
        format!("{{{}}}", parts.join(","))
    }
}

fn escape(value: &str) -> String {
    // The legacy encoder only escaped backslashes and quotes.
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

/// `socks5` / `http`, anything else falling back to `socks5`.
pub fn protocol_or_default(value: &str) -> &'static str {
    normalize_protocol(value).unwrap_or("socks5")
}

/// `apps` exactly, anything else falling back to `all`.
pub fn scope_or_default(value: &str) -> &'static str {
    normalize_scope(value)
}

/// Deduplicates package names in their original order. Package names cannot contain newlines, so a
/// newline-separated payload is the smallest JNI layout that keeps the filtering rule here.
pub fn filter_targets(text: &str) -> String {
    let mut targets: Vec<&str> = Vec::new();
    for line in text.split('\n') {
        if line.trim().is_empty() || targets.contains(&line) {
            continue;
        }
        targets.push(line);
    }
    targets.join("\n")
}

fn text_like(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

/// Newline-separated package names from the engine JSON, or `None` when there is no `packages`
/// array (the caller then leaves the document untouched).
pub fn packages_of(proxy_json: &str) -> Option<String> {
    let value: Value = serde_json::from_str(proxy_json).ok()?;
    let packages = value.as_object()?.get("packages")?.as_array()?;
    Some(
        packages
            .iter()
            .map(text_like)
            .collect::<Vec<String>>()
            .join("\n"),
    )
}

/// Replaces `packages` with the resolved `uids`; `None` means "not a per-app document".
pub fn apply_uids(proxy_json: &str, uids_csv: &str) -> Option<String> {
    let mut value: Value = serde_json::from_str(proxy_json).ok()?;
    let object = value.as_object_mut()?;
    if !object.get("packages")?.is_array() {
        return None;
    }
    object.remove("packages");
    let mut uids: Vec<i64> = Vec::new();
    for part in uids_csv.split(',') {
        let Ok(uid) = part.trim().parse::<i64>() else {
            continue;
        };
        if uid > 0 && !uids.contains(&uid) {
            uids.push(uid);
        }
    }
    object.insert(
        "uids".to_string(),
        Value::Array(uids.into_iter().map(Value::from).collect()),
    );
    serde_json::to_string(&value).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn config() -> AppConfig {
        AppConfig {
            enabled: true,
            protocol: "socks5".to_string(),
            host: "127.0.0.1".to_string(),
            port: 7890,
            proxy_app_package: "com.proxy".to_string(),
            scope: "all".to_string(),
            ..AppConfig::default()
        }
    }

    #[test]
    fn validation_follows_the_legacy_order() {
        let mut value = config();
        value.host = "bad".to_string();
        value.port = 0;
        assert_eq!(value.validation_error(None, None), Some("host"));
        value.host = "127.0.0.1".to_string();
        assert_eq!(value.validation_error(None, None), Some("port"));
        value.port = 7890;
        value.proxy_app_package = " ".to_string();
        assert_eq!(value.validation_error(None, None), Some("proxyAppRequired"));
    }

    #[test]
    fn self_and_installed_package_checks_are_distinct() {
        let mut value = config();
        assert_eq!(
            value.validation_error(Some("com.proxy"), None),
            Some("proxyAppSelf")
        );
        assert_eq!(
            value.validation_error(None, Some(&["com.other".to_string()])),
            Some("proxyAppMissing")
        );
        assert_eq!(value.validation_error(None, None), None);
        value.proxy_app_package = "com.gone".to_string();
        assert_eq!(
            value.validation_error(None, Some(&["com.proxy".to_string()])),
            Some("proxyAppMissing")
        );
    }

    #[test]
    fn credentials_are_limited_in_utf8_bytes() {
        let mut value = config();
        value.username = "u".repeat(255);
        assert_eq!(value.validation_error(None, None), None);
        value.username = "u".repeat(256);
        assert_eq!(value.validation_error(None, None), Some("credentials"));
    }

    #[test]
    fn per_app_scope_needs_one_target_after_filtering() {
        let mut value = config();
        value.scope = "apps".to_string();
        value.target_packages = vec!["com.proxy".to_string(), String::new()];
        assert_eq!(value.validation_error(None, None), Some("targets"));
        value.target_packages.push("com.a".to_string());
        assert_eq!(value.validation_error(None, None), None);
        assert_eq!(value.effective_targets(), vec!["com.a".to_string()]);
    }

    #[test]
    fn engine_json_matches_the_legacy_shape() {
        let mut value = config();
        value.enabled = false;
        value.proxy_app_package = String::new();
        assert_eq!(
            value.engine_json(),
            "{\"enabled\":false,\"protocol\":\"socks5\",\"host\":\"127.0.0.1\",".to_string()
                + "\"port\":7890,\"username\":\"\",\"password\":\"\"}"
        );
    }

    #[test]
    fn per_app_engine_json_sorts_and_drops_the_proxy_app() {
        let mut value = config();
        value.scope = "apps".to_string();
        value.target_packages = vec![
            "com.b".to_string(),
            "com.proxy".to_string(),
            "com.a".to_string(),
            "com.a".to_string(),
        ];
        assert!(value
            .engine_json()
            .ends_with(",\"scope\":\"apps\",\"packages\":[\"com.a\",\"com.b\"]}"));
    }

    #[test]
    fn protocol_scope_and_targets_normalize_like_the_bridge() {
        assert_eq!(protocol_or_default(" SOCKS5 "), "socks5");
        assert_eq!(protocol_or_default("HTTP"), "http");
        assert_eq!(protocol_or_default("quic"), "socks5");
        assert_eq!(scope_or_default(" APPS "), "apps");
        assert_eq!(scope_or_default("weird"), "all");
        assert_eq!(filter_targets("a\n\n a\nb\n"), "a\n a\nb");
    }

    #[test]
    fn packages_and_uids_rewrite_only_per_app_documents() {
        let json = r#"{"enabled":true,"scope":"apps","packages":["com.a","com.b"]}"#;
        assert_eq!(packages_of(json).as_deref(), Some("com.a\ncom.b"));
        let rewritten = apply_uids(json, "10001,10002,10001,0").unwrap();
        assert!(rewritten.contains("\"uids\":[10001,10002]"));
        assert!(!rewritten.contains("\"packages\""));

        assert_eq!(packages_of(r#"{"enabled":true}"#), None);
        assert_eq!(apply_uids(r#"{"enabled":true}"#, "1"), None);
        assert_eq!(apply_uids("not json", "1"), None);
        let empty = apply_uids(r#"{"enabled":true,"packages":[]}"#, "");
        assert!(empty.unwrap().contains("\"uids\":[]"));
    }

    #[test]
    fn dart_map_defaults_are_the_legacy_form_defaults() {
        let value = AppConfig::from_value(&json!({})).unwrap();
        assert_eq!(value.protocol, "socks5");
        assert_eq!(value.host, "127.0.0.1");
        assert_eq!(value.port, 7890);
        assert_eq!(value.scope, "all");
        assert!(value.target_packages.is_empty());
    }
}

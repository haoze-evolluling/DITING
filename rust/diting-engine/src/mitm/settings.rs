//! The MITM configuration Kotlin pushes independently of the session: cosmetic rules, request rules
//! and the HTTP event callback.
//!
//! All three were engine fields in Go (`SetCosmeticRules`, `SetRequestRules`, `httpLogCallback`) and
//! are read on the relay's hot path, so they are published behind a lock as an `Arc` and cloned
//! before use: a settings push during a page load changes nothing about the page in flight.
//!
//! The payload shapes are Kotlin's, so the JSON decode stays here (`encoding/json` did it in Go) and
//! the compiled form is the kernel's:
//!
//! ```text
//! cosmetic: {"globalHide":[…],"globalException":[…],
//!            "domains":{"example.com":{"hide":[…],"exception":[…]}}}
//! request : [{"pattern":"https://example.com/path","kind":"block"}]
//! ```

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};

use diting_cosmetic_core::{DomainRules, RuleSet, Rules};
use diting_request_core::match_rule;
use diting_request_core::rules::{normalize_all, Rule};

/// `HttpLogCallback.onHttpEvent(String, String, String, String, String)`, installed by Kotlin.
pub trait HttpLogSink: Send + Sync + 'static {
    /// `(package, authority, protocol, outcome, matched rule)`.
    fn event(&self, package: &str, authority: &str, protocol: &str, outcome: &str, rule: &str);
}

/// The three pushed settings.
pub struct MitmSettings {
    cosmetic: RwLock<Arc<RuleSet>>,
    cosmetic_payload_bytes: AtomicU64,
    requests: RwLock<Arc<Vec<Rule>>>,
    http_log: RwLock<Option<Arc<dyn HttpLogSink>>>,
}

impl Default for MitmSettings {
    fn default() -> Self {
        Self::new()
    }
}

impl MitmSettings {
    pub fn new() -> Self {
        Self {
            cosmetic: RwLock::new(Arc::new(RuleSet::Empty)),
            cosmetic_payload_bytes: AtomicU64::new(0),
            requests: RwLock::new(Arc::new(Vec::new())),
            http_log: RwLock::new(None),
        }
    }

    /// `SetCosmeticRules`: an empty payload disables injection, an undecodable one still injects the
    /// `<link>` but serves the "invalid rules" sentinel stylesheet (that is the kernel's split).
    pub fn set_cosmetic_rules(&self, payload: &str) {
        let bytes = payload.len() as u64;
        let compiled = compile_cosmetic(payload);
        *self
            .cosmetic
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Arc::new(compiled);
        self.cosmetic_payload_bytes.store(bytes, Ordering::Release);
    }

    /// `cosmeticRulesEmpty()`: injection is skipped entirely without a payload.
    pub fn cosmetic_rules_empty(&self) -> bool {
        self.cosmetic().is_empty()
    }

    pub fn cosmetic(&self) -> Arc<RuleSet> {
        self.cosmetic
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// `len(cosmeticCSS)`: the `/health` route reports it as `css_bytes`.
    pub fn cosmetic_payload_bytes(&self) -> u64 {
        self.cosmetic_payload_bytes.load(Ordering::Acquire)
    }

    /// `SetRequestRules`: a malformed payload leaves the previous table in place, and the rules the
    /// kernel cannot match are dropped silently.
    pub fn set_request_rules(&self, payload: &str) -> Result<(), String> {
        if payload.trim().is_empty() {
            *self
                .requests
                .write()
                .unwrap_or_else(|error| error.into_inner()) = Arc::new(Vec::new());
            return Ok(());
        }
        #[derive(serde::Deserialize)]
        struct RawRule {
            #[serde(default)]
            pattern: String,
            #[serde(default)]
            kind: String,
        }
        let decoded: Vec<RawRule> = serde_json::from_str(payload)
            .map_err(|error| format!("SetRequestRules: invalid JSON: {error}"))?;
        let pairs: Vec<(String, String)> = decoded
            .into_iter()
            .map(|rule| (rule.kind, rule.pattern))
            .collect();
        *self
            .requests
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Arc::new(normalize_all(&pairs));
        Ok(())
    }

    pub fn requests(&self) -> Arc<Vec<Rule>> {
        self.requests
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// `requestFilterDecision`: the URL rules first, then the domain fallback the caller runs.
    ///
    /// `None` means no rule matched, so the caller has to ask the domain-rules kernel about
    /// `decision.domain_host` (which is the host with its default port stripped).
    pub fn request_decision(
        &self,
        scheme: &str,
        host: &str,
        path: &str,
    ) -> Option<match_rule::Decision> {
        let rules = self.requests();
        if rules.is_empty() {
            return None;
        }
        Some(match_rule::decide(&rules, scheme, host, path))
    }

    /// `setHttpLogCallback`; a null stops reporting.
    pub fn set_http_log(&self, sink: Option<Arc<dyn HttpLogSink>>) {
        *self
            .http_log
            .write()
            .unwrap_or_else(|error| error.into_inner()) = sink;
    }

    pub fn http_log(&self) -> Option<Arc<dyn HttpLogSink>> {
        self.http_log
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// `logHTTPEvent`: one row per relay decision, `unknown` when the flow has no package.
    pub fn log_http(
        &self,
        package: &str,
        authority: &str,
        protocol: &str,
        outcome: &str,
        rule: &str,
    ) {
        let Some(sink) = self.http_log() else {
            return;
        };
        let package = if package.is_empty() {
            "unknown"
        } else {
            package
        };
        sink.event(package, authority, protocol, outcome, rule);
    }
}

/// The cosmetic payload as the kernel wants it.
fn compile_cosmetic(payload: &str) -> RuleSet {
    if payload.trim().is_empty() {
        return RuleSet::Empty;
    }
    #[derive(serde::Deserialize, Default)]
    #[serde(default, rename_all = "camelCase")]
    struct RawDomain {
        hide: Vec<String>,
        exception: Vec<String>,
    }
    #[derive(serde::Deserialize, Default)]
    #[serde(default, rename_all = "camelCase")]
    struct RawRules {
        global_hide: Vec<String>,
        global_exception: Vec<String>,
        domains: HashMap<String, RawDomain>,
    }
    match serde_json::from_str::<RawRules>(payload) {
        Ok(raw) => RuleSet::Loaded(Rules {
            global_hide: raw.global_hide,
            global_exception: raw.global_exception,
            domains: raw
                .domains
                .into_iter()
                .map(|(host, rules)| {
                    (
                        host,
                        DomainRules {
                            hide: rules.hide,
                            exception: rules.exception,
                        },
                    )
                })
                .collect(),
        }),
        Err(_) => RuleSet::Invalid,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_payload_disables_injection() {
        let settings = MitmSettings::new();
        assert!(settings.cosmetic_rules_empty());
        settings.set_cosmetic_rules("   ");
        assert!(settings.cosmetic_rules_empty());
        assert_eq!(settings.cosmetic_payload_bytes(), 3);
    }

    #[test]
    fn a_loaded_payload_renders_the_scoped_stylesheet() {
        let settings = MitmSettings::new();
        settings.set_cosmetic_rules(
            r##"{"globalHide":["#ad"],"globalException":[],
                "domains":{"example.com":{"hide":[".banner"],"exception":[]}}}"##,
        );
        assert!(!settings.cosmetic_rules_empty());
        let css = settings.cosmetic().render("ads.example.com");
        assert!(css.contains("#ad { display: none !important; }"), "{css}");
        assert!(
            css.contains(".banner { display: none !important; }"),
            "{css}"
        );
    }

    #[test]
    fn an_undecodable_payload_still_injects() {
        let settings = MitmSettings::new();
        settings.set_cosmetic_rules("{");
        assert!(!settings.cosmetic_rules_empty());
        assert_eq!(
            settings.cosmetic().render("example.com"),
            "/* DITING: invalid cosmetic rules */"
        );
    }

    #[test]
    fn request_rules_keep_only_the_matchable_ones() {
        let settings = MitmSettings::new();
        settings
            .set_request_rules(
                r#"[{"pattern":"https://ads.test/p","kind":"block"},
                    {"pattern":"https://ok.test/","kind":"allow"},
                    {"pattern":"https://nope.test/","kind":"deny"},
                    {"pattern":"nope.test","kind":"block"}]"#,
            )
            .expect("valid payload");
        assert_eq!(settings.requests().len(), 2);
        let decision = settings
            .request_decision("https", "ads.test", "/p?x=1")
            .expect("a decision");
        assert!(decision.matched && decision.blocked);
    }

    #[test]
    fn a_malformed_request_payload_is_reported() {
        let settings = MitmSettings::new();
        let error = settings.set_request_rules("{").expect_err("invalid");
        assert!(
            error.starts_with("SetRequestRules: invalid JSON: "),
            "{error}"
        );
    }
}

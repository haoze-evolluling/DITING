//! The network context, the per-profile match predicate and [`resolve`], the whole decision.

use serde_json::Value;

/// The normalized network facts Kotlin reads from `ConnectivityManager` (plus the SSID/BSSID that
/// only Wi-Fi exposes). `kind` is a free token — `wifi` / `cellular` / `ethernet` / `vpn` / `none` /
/// `other` — compared case-insensitively against a profile's `types` list.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NetworkContext {
    pub kind: String,
    pub metered: bool,
    pub roaming: bool,
    pub validated: bool,
    pub ssid: String,
    pub bssid: String,
}

/// One profile's network predicate. Every field is optional: an empty `types` list is "any net" and
/// an absent boolean (or absent ssid/bssid) is "don't care".
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NetworkMatch {
    pub types: Vec<String>,
    pub metered: Option<bool>,
    pub roaming: Option<bool>,
    pub validated: Option<bool>,
    pub ssid: Option<String>,
    pub bssid: Option<String>,
}

/// The parts of a profile the resolver returns (the config reference, not the whole document).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub priority: i64,
    pub enabled: bool,
    pub network_match: NetworkMatch,
    pub upstream_set: String,
    pub rule_group_states: Vec<String>,
    pub feature_toggles: Value,
}

/// The effective configuration reference for one network context.
#[derive(Clone, Debug, PartialEq)]
pub struct Resolution {
    /// True when a profile's predicate matched; false when `fallback_id` supplied the answer.
    pub matched: bool,
    pub profile_id: String,
    pub name: String,
    pub upstream_set: String,
    pub rule_group_states: Vec<String>,
    pub feature_toggles: Value,
    /// Human-readable why (editor timeline / diagnostics), never parsed by the caller.
    pub reason: String,
}

impl Default for Resolution {
    fn default() -> Self {
        Resolution {
            matched: false,
            profile_id: String::new(),
            name: String::new(),
            upstream_set: String::new(),
            rule_group_states: Vec::new(),
            feature_toggles: Value::Object(Default::default()),
            reason: String::from("no profile matched"),
        }
    }
}

/// Matches one wildcard pattern. Supports a single `*` (`*` alone = any; `pre*` = prefix;
/// `*suf` = suffix; `*mid*` = contains; otherwise exact), so an SSID rule can be `Office*`.
fn wildcard_match(pattern: &str, value: &str) -> bool {
    let pattern = pattern.trim();
    if pattern.is_empty() {
        return true;
    }
    match (pattern.starts_with('*'), pattern.ends_with('*')) {
        (true, true) => {
            let inner = &pattern[1..pattern.len() - 1];
            inner.is_empty() || value.contains(inner)
        }
        (true, false) => value.ends_with(&pattern[1..]),
        (false, true) => value.starts_with(&pattern[..pattern.len() - 1]),
        (false, false) => value.eq_ignore_ascii_case(pattern),
    }
}

impl NetworkMatch {
    /// True when this predicate accepts `context`. A field left unset never rejects.
    pub fn matches(&self, context: &NetworkContext) -> bool {
        let type_ok = self.types.is_empty()
            || self
                .types
                .iter()
                .any(|candidate| candidate.eq_ignore_ascii_case(&context.kind));
        if !type_ok {
            return false;
        }
        if let Some(metered) = self.metered {
            if metered != context.metered {
                return false;
            }
        }
        if let Some(roaming) = self.roaming {
            if roaming != context.roaming {
                return false;
            }
        }
        if let Some(validated) = self.validated {
            if validated != context.validated {
                return false;
            }
        }
        if let Some(ssid) = &self.ssid {
            if !wildcard_match(ssid, &context.ssid) {
                return false;
            }
        }
        if let Some(bssid) = &self.bssid {
            if !wildcard_match(bssid, &context.bssid) {
                return false;
            }
        }
        true
    }
}

fn resolution_of(profile: &Profile, matched: bool, reason: String) -> Resolution {
    Resolution {
        matched,
        profile_id: profile.id.clone(),
        name: profile.name.clone(),
        upstream_set: profile.upstream_set.clone(),
        rule_group_states: profile.rule_group_states.clone(),
        feature_toggles: profile.feature_toggles.clone(),
        reason,
    }
}

/// Resolves the effective profile for `context`.
///
/// Candidates are the enabled profiles whose predicate matches. The highest `priority` wins; on a
/// tie the first one in input order wins (a stable, explainable rule the editor can show). When no
/// profile matches, the profile named by `fallback_id` (if enabled) is returned with
/// `matched == false`; otherwise an empty resolution says "no profile matched".
pub fn resolve(context: &NetworkContext, profiles: &[Profile], fallback_id: &str) -> Resolution {
    let mut best: Option<&Profile> = None;
    for profile in profiles.iter().filter(|profile| profile.enabled) {
        if !profile.network_match.matches(context) {
            continue;
        }
        match best {
            Some(current) if current.priority >= profile.priority => {}
            _ => best = Some(profile),
        }
    }
    if let Some(profile) = best {
        let reason = format!("匹配档案 {} (priority={})", profile.name, profile.priority);
        return resolution_of(profile, true, reason);
    }
    if !fallback_id.is_empty() {
        if let Some(profile) = profiles
            .iter()
            .find(|profile| profile.enabled && profile.id == fallback_id)
        {
            let reason = format!("无匹配，使用回退档案 {}", profile.name);
            return resolution_of(profile, false, reason);
        }
    }
    Resolution::default()
}

impl Resolution {
    /// The JSON answer the JNI/FFI caller parses.
    pub fn to_json(&self) -> Value {
        serde_json::json!({
            "matched": self.matched,
            "profileId": self.profile_id,
            "name": self.name,
            "upstreamSet": self.upstream_set,
            "ruleGroupStates": self.rule_group_states,
            "featureToggles": self.feature_toggles,
            "reason": self.reason,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn ctx(kind: &str) -> NetworkContext {
        NetworkContext {
            kind: kind.to_string(),
            ..Default::default()
        }
    }

    fn wifi_profile(id: &str, priority: i64) -> Profile {
        Profile {
            id: id.to_string(),
            name: id.to_string(),
            priority,
            enabled: true,
            network_match: NetworkMatch {
                types: vec!["wifi".to_string()],
                ..Default::default()
            },
            upstream_set: format!("{id}-up"),
            rule_group_states: vec!["ads".to_string()],
            feature_toggles: json!({ "blocking": true }),
        }
    }

    fn cell_profile(id: &str, priority: i64) -> Profile {
        Profile {
            id: id.to_string(),
            name: id.to_string(),
            priority,
            enabled: true,
            network_match: NetworkMatch {
                types: vec!["cellular".to_string()],
                ..Default::default()
            },
            upstream_set: format!("{id}-up"),
            rule_group_states: vec![],
            feature_toggles: json!({}),
        }
    }

    #[test]
    fn type_selects_the_profile() {
        let profiles = vec![wifi_profile("home", 10), cell_profile("mobile", 10)];
        let wifi = resolve(&ctx("wifi"), &profiles, "");
        assert!(wifi.matched);
        assert_eq!(wifi.profile_id, "home");
        let cell = resolve(&ctx("cellular"), &profiles, "");
        assert_eq!(cell.profile_id, "mobile");
    }

    #[test]
    fn higher_priority_wins() {
        let mut low = wifi_profile("low", 10);
        low.network_match.ssid = Some("Office".to_string());
        let mut high = wifi_profile("high", 100);
        high.network_match.ssid = Some("Office".to_string());
        let profiles = vec![low, high];
        let mut context = ctx("wifi");
        context.ssid = "Office".to_string();
        assert_eq!(resolve(&context, &profiles, "").profile_id, "high");
    }

    #[test]
    fn tie_keeps_the_first_in_input_order() {
        let a = wifi_profile("aa", 50);
        let b = wifi_profile("bb", 50);
        let profiles = vec![a, b];
        assert_eq!(resolve(&ctx("wifi"), &profiles, "").profile_id, "aa");
    }

    #[test]
    fn metered_and_roaming_are_respected() {
        let mut profile = wifi_profile("guarded", 10);
        profile.network_match.metered = Some(false);
        profile.network_match.roaming = Some(false);
        let profiles = vec![profile];
        let mut metered = ctx("wifi");
        metered.metered = true;
        assert!(!resolve(&metered, &profiles, "").matched);
        let free = ctx("wifi");
        assert!(resolve(&free, &profiles, "").matched);
    }

    #[test]
    fn ssid_wildcard_prefix() {
        let mut profile = wifi_profile("office", 10);
        profile.network_match.ssid = Some("Office*".to_string());
        let profiles = vec![profile];
        let mut context = ctx("wifi");
        context.ssid = "Office-Guest".to_string();
        assert_eq!(resolve(&context, &profiles, "").profile_id, "office");
        context.ssid = "Home".to_string();
        assert!(!resolve(&context, &profiles, "").matched);
    }

    #[test]
    fn unmatched_falls_back_by_id() {
        let profiles = vec![wifi_profile("home", 10)];
        let resolved = resolve(&ctx("cellular"), &profiles, "home");
        assert!(!resolved.matched);
        assert_eq!(resolved.profile_id, "home");
        assert!(resolved.reason.contains("回退"));
    }

    #[test]
    fn unmatched_without_fallback_is_empty() {
        let profiles = vec![wifi_profile("home", 10)];
        let resolved = resolve(&ctx("cellular"), &profiles, "");
        assert!(!resolved.matched);
        assert!(resolved.profile_id.is_empty());
    }

    #[test]
    fn disabled_profile_is_never_selected_even_as_fallback() {
        let mut profile = wifi_profile("home", 10);
        profile.enabled = false;
        let profiles = vec![profile];
        assert!(resolve(&ctx("wifi"), &profiles, "home")
            .profile_id
            .is_empty());
    }

    #[test]
    fn json_shape_is_stable() {
        let profiles = vec![wifi_profile("home", 10)];
        let value = resolve(&ctx("wifi"), &profiles, "").to_json();
        assert_eq!(value["matched"], json!(true));
        assert_eq!(value["profileId"], json!("home"));
        assert_eq!(value["upstreamSet"], json!("home-up"));
        assert_eq!(value["featureToggles"]["blocking"], json!(true));
    }
}

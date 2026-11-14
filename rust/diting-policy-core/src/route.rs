//! Conditional routing — the decision's *second output* (N2).
//!
//! The policy kernel already answers `allow` / `block`. Conditional routing asks a second, additive
//! question for the same query: *if allowed, which upstream / outbound should carry it, and what is
//! the ordered fallback chain?* This module owns that pure evaluation over a caller-supplied rule
//! list. Nothing here changes the `Decision` walk or the rule tables: a snapshot that carries no
//! route rules answers exactly as before, which is what lets the feature land without a rule
//! regression (see the phase-2 risk register, "新字段只增不改").
//!
//! Field names follow sing-box's `route_rule`: `upstream_tag` / `outbound_tag` / `fallback_chain`.
//! The runtime that consumes the answer (upstream-core / resolver-core) is wired separately; this is
//! the single implementation of *which rule wins*.

use serde_json::Value;

/// What a route rule's `pattern` is compared against.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MatchKind {
    /// The owning package, matched exactly (`com.example.app`).
    App,
    /// A domain, matched as the domain itself or any sub-domain (`example.com` →
    /// `example.com`, `a.example.com`; `*.example.com` → sub-domains only; `.example.com` →
    /// suffix).
    Domain,
    /// A geosite category. The pure kernel has no geosite database, so a `Geosite` rule never
    /// matches here; it is kept so a snapshot can round-trip one until the geosite resolver lands.
    Geosite,
}

impl MatchKind {
    pub fn parse(value: &str) -> MatchKind {
        match value {
            "app" => MatchKind::App,
            "geosite" => MatchKind::Geosite,
            _ => MatchKind::Domain,
        }
    }
}

/// One route rule: priority (higher first), matcher and the tags it assigns.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RouteRule {
    pub priority: i64,
    pub kind: MatchKind,
    pub pattern: String,
    pub upstream_tag: String,
    pub outbound_tag: String,
    pub fallback_chain: Vec<String>,
}

/// The second output for one query.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RouteDecision {
    pub matched: bool,
    pub rule_pattern: String,
    pub upstream_tag: String,
    pub outbound_tag: String,
    pub fallback_chain: Vec<String>,
    pub reason: String,
}

fn domain_matches(pattern: &str, host: &str) -> bool {
    let pattern = pattern.trim().trim_end_matches('.').to_ascii_lowercase();
    let host = host.trim().trim_end_matches('.').to_ascii_lowercase();
    if pattern.is_empty() || host.is_empty() {
        return false;
    }
    if let Some(rest) = pattern.strip_prefix("*.") {
        // `*.example.com` matches `a.example.com` (and deeper) but not `example.com` itself.
        return host.len() > rest.len() && host.ends_with(rest) && host.as_bytes()[host.len() - rest.len() - 1] == b'.';
    }
    if let Some(rest) = pattern.strip_prefix('.') {
        return host.ends_with(rest) && host.len() > rest.len();
    }
    // Bare domain: the host itself or any sub-domain.
    host == pattern
        || (host.len() > pattern.len()
            && host.ends_with(&pattern)
            && host.as_bytes()[host.len() - pattern.len() - 1] == b'.')
}

fn rule_matches(rule: &RouteRule, host: &str, app: &str) -> bool {
    match rule.kind {
        MatchKind::Domain => domain_matches(&rule.pattern, host),
        MatchKind::App => !app.is_empty() && app.eq_ignore_ascii_case(rule.pattern.trim()),
        MatchKind::Geosite => false,
    }
}

/// Evaluates the route rules against one query. The highest-priority matching rule wins; ties keep
/// the earliest input order (stable and explainable, like the profile resolver). No match yields a
/// default decision (`matched == false`) the caller renders as "default outbound".
pub fn evaluate(rules: &[RouteRule], host: &str, app: &str) -> RouteDecision {
    let mut order: Vec<&RouteRule> = rules.iter().collect();
    // Stable sort, so equal priorities preserve input order.
    order.sort_by_key(|rule| std::cmp::Reverse(rule.priority));
    for rule in order {
        if rule_matches(rule, host, app) {
            return RouteDecision {
                matched: true,
                rule_pattern: rule.pattern.clone(),
                upstream_tag: rule.upstream_tag.clone(),
                outbound_tag: rule.outbound_tag.clone(),
                fallback_chain: rule.fallback_chain.clone(),
                reason: format!("命中路由规则 {} (priority={})", rule.pattern, rule.priority),
            };
        }
    }
    RouteDecision {
        matched: false,
        reason: "无路由规则命中，使用默认出口".to_string(),
        ..Default::default()
    }
}

impl RouteDecision {
    /// The JSON view the editor preview and any future FFI caller share.
    pub fn to_json(&self) -> Value {
        serde_json::json!({
            "matched": self.matched,
            "rulePattern": self.rule_pattern,
            "upstreamTag": self.upstream_tag,
            "outboundTag": self.outbound_tag,
            "fallbackChain": self.fallback_chain,
            "reason": self.reason,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule(kind: MatchKind, pattern: &str, priority: i64, tag: &str) -> RouteRule {
        RouteRule {
            priority,
            kind,
            pattern: pattern.to_string(),
            upstream_tag: tag.to_string(),
            outbound_tag: format!("{tag}-out"),
            fallback_chain: vec!["fallback-a".to_string(), "fallback-b".to_string()],
        }
    }

    #[test]
    fn bare_domain_matches_subdomains() {
        let rules = vec![rule(MatchKind::Domain, "example.com", 10, "cn")];
        assert!(evaluate(&rules, "example.com", "").matched);
        assert!(evaluate(&rules, "api.example.com", "").matched);
        assert!(!evaluate(&rules, "notexample.com", "").matched);
        assert!(!evaluate(&rules, "example.com.evil.net", "").matched);
    }

    #[test]
    fn wildcard_domain_skips_the_apex() {
        let rules = vec![rule(MatchKind::Domain, "*.example.com", 10, "cn")];
        assert!(!evaluate(&rules, "example.com", "").matched);
        assert!(evaluate(&rules, "a.example.com", "").matched);
    }

    #[test]
    fn app_rule_matches_package() {
        let rules = vec![rule(MatchKind::App, "com.game.app", 10, "game")];
        let decision = evaluate(&rules, "whatever.net", "com.game.app");
        assert!(decision.matched);
        assert_eq!(decision.upstream_tag, "game");
        assert!(!evaluate(&rules, "whatever.net", "com.other").matched);
    }

    #[test]
    fn higher_priority_wins() {
        let rules = vec![
            rule(MatchKind::Domain, "example.com", 10, "low"),
            rule(MatchKind::Domain, "example.com", 100, "high"),
        ];
        assert_eq!(evaluate(&rules, "example.com", "").upstream_tag, "high");
    }

    #[test]
    fn equal_priority_keeps_input_order() {
        let rules = vec![
            rule(MatchKind::Domain, "example.com", 50, "first"),
            rule(MatchKind::Domain, "example.com", 50, "second"),
        ];
        assert_eq!(evaluate(&rules, "example.com", "").upstream_tag, "first");
    }

    #[test]
    fn no_match_is_a_default_decision() {
        let rules = vec![rule(MatchKind::Domain, "example.com", 10, "cn")];
        let decision = evaluate(&rules, "other.net", "");
        assert!(!decision.matched);
        assert!(decision.upstream_tag.is_empty());
        assert!(decision.reason.contains("默认出口"));
    }

    #[test]
    fn fallback_chain_is_passed_through() {
        let rules = vec![rule(MatchKind::Domain, "example.com", 10, "cn")];
        let decision = evaluate(&rules, "example.com", "");
        assert_eq!(
            decision.fallback_chain,
            vec!["fallback-a".to_string(), "fallback-b".to_string()]
        );
    }

    #[test]
    fn geosite_never_matches_without_a_database() {
        let rules = vec![rule(MatchKind::Geosite, "category-ads", 10, "block")];
        assert!(!evaluate(&rules, "ads.example.com", "").matched);
    }

    #[test]
    fn json_shape_is_stable() {
        let rules = vec![rule(MatchKind::Domain, "example.com", 10, "cn")];
        let value = evaluate(&rules, "api.example.com", "").to_json();
        assert_eq!(value["matched"], serde_json::json!(true));
        assert_eq!(value["upstreamTag"], serde_json::json!("cn"));
        assert_eq!(value["outboundTag"], serde_json::json!("cn-out"));
    }
}

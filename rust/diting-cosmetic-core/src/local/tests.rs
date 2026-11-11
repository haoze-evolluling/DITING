//! Unit tests for the local asset server: the host match, the routes and the fixed headers.

use super::*;
use crate::rules::DomainRules;
use crate::rules::{RuleSet, Rules};
use std::collections::HashMap;

fn loaded(domains: &[(&str, &[&str])]) -> RuleSet {
    let mut map = HashMap::new();
    for (domain, hide) in domains {
        map.insert(
            (*domain).to_string(),
            DomainRules {
                hide: hide.iter().map(|item| (*item).to_string()).collect(),
                exception: Vec::new(),
            },
        );
    }
    RuleSet::Loaded(Rules {
        global_hide: vec![".global".to_string()],
        global_exception: Vec::new(),
        domains: map,
    })
}

fn header<'a>(response: &'a Response, name: &str) -> Option<&'a str> {
    response
        .headers
        .iter()
        .find(|(key, _)| *key == name)
        .map(|(_, value)| value.as_str())
}

#[test]
fn only_the_asset_host_matches() {
    assert!(is_asset_host("local.pwhs.app"));
    assert!(is_asset_host(" Local.PWHS.app "));
    assert!(is_asset_host("local.pwhs.app:8443"));
    // The old helper cut at the last colon whatever came before it.
    assert!(!is_asset_host("[::1]:443"));
    assert!(!is_asset_host("::1"));
    assert!(!is_asset_host("ads.local.pwhs.app"));
    assert!(!is_asset_host(""));
}

#[test]
fn the_stylesheet_route_serves_the_scoped_css() {
    let rules = loaded(&[("example.com", &[".banner"])]);
    let response = respond("/cosmetic.css", "Ads.Example.com:443", &rules, 123);
    assert_eq!(response.status, 200);
    assert_eq!(response.content_type, "text/css; charset=utf-8");
    assert_eq!(
        response.body,
        ".banner { display: none !important; }\n.global { display: none !important; }\n"
    );
    assert_eq!(
        header(&response, "Content-Length"),
        Some(response.body.len().to_string().as_str())
    );
    // The stylesheet depends on the page host, so it must not be shared between sites.
    assert_eq!(
        header(&response, "Cache-Control"),
        Some("private, max-age=300")
    );
    assert_eq!(header(&response, "Vary"), Some("X-DITING-Host"));
    assert_eq!(header(&response, "Access-Control-Allow-Origin"), Some("*"));
    assert_eq!(header(&response, "X-DITING"), Some("local-asset-server"));
    assert_eq!(
        header(&response, "Content-Type"),
        Some("text/css; charset=utf-8")
    );
}

#[test]
fn a_missing_host_query_serves_the_unscoped_stylesheet() {
    let rules = loaded(&[("example.com", &[".banner"])]);
    let response = respond("/cosmetic.css", "", &rules, 0);
    assert_eq!(response.body, ".global { display: none !important; }\n");
}

#[test]
fn the_health_route_reports_the_payload_size() {
    let response = respond("/health", "", &RuleSet::Empty, 4096);
    assert_eq!(response.status, 200);
    assert_eq!(response.content_type, "application/json");
    assert_eq!(response.body, r#"{"status":"ok","css_bytes":4096}"#);
    // `/health` is shareable, unlike the stylesheet.
    assert_eq!(
        header(&response, "Cache-Control"),
        Some("public, max-age=300")
    );
    assert_eq!(header(&response, "Vary"), None);
}

#[test]
fn an_unknown_path_is_a_plain_404() {
    let response = respond("/favicon.ico", "", &RuleSet::Empty, 0);
    assert_eq!(response.status, 404);
    assert_eq!(response.content_type, "text/plain");
    assert_eq!(response.body, "Not Found");
    assert_eq!(header(&response, "Content-Length"), Some("9"));
}

#[test]
fn an_empty_rule_set_serves_the_sentinel() {
    let response = respond("/cosmetic.css", "example.com", &RuleSet::Empty, 0);
    assert_eq!(response.body, crate::rules::NO_RULES);
    let invalid = respond("/cosmetic.css", "example.com", &RuleSet::Invalid, 0);
    assert_eq!(invalid.body, crate::rules::INVALID_RULES);
}

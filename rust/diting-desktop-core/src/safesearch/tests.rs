use super::*;
use diting_desktop_api::config::SafeSearchConfig;

fn enabled_config() -> SafeSearchConfig {
    SafeSearchConfig {
        enabled: true,
        disabled: Vec::new(),
        ttl: 0,
    }
}

#[test]
fn default_is_disabled() {
    let engine = SafeSearchEngine::new(&SafeSearchConfig::default());
    assert!(!engine.enabled());
    assert!(engine.lookup("www.google.com", TYPE_A).is_none());
    assert_eq!(engine.services(), SERVICES.to_vec());
    assert_eq!(engine.stats().ttl, DEFAULT_SAFESEARCH_TTL);
    assert_eq!(default_ttl(), 300);
}

#[test]
fn google_covers_tlds_with_cname() {
    let engine = SafeSearchEngine::new(&enabled_config());
    for domain in ["www.google.com", "www.google.co.uk", "www.google.de"] {
        let result = engine.lookup(domain, TYPE_A).unwrap();
        assert_eq!(result.service, "google");
        assert_eq!(result.cname, "forcesafesearch.google.com.");
        assert_eq!(result.ip, None);
        assert!(!result.nodata);
    }
}

#[test]
fn yandex_uses_a_record_and_nodata_for_aaaa() {
    let engine = SafeSearchEngine::new(&enabled_config());
    let result = engine.lookup("yandex.ru", TYPE_A).unwrap();
    assert_eq!(result.service, "yandex");
    assert_eq!(result.ip, Some("213.180.193.56".parse().unwrap()));
    assert_eq!(result.ip_type, TYPE_A);

    let result = engine.lookup("yandex.ru", TYPE_AAAA).unwrap();
    assert!(result.nodata);
    assert_eq!(result.ip, None);
}

#[test]
fn per_service_toggle() {
    let engine = SafeSearchEngine::new(&SafeSearchConfig {
        enabled: true,
        disabled: vec!["google".to_string()],
        ttl: 0,
    });
    assert!(engine.lookup("www.google.com", TYPE_A).is_none());
    assert!(engine.lookup("www.bing.com", TYPE_A).is_some());
    assert_eq!(engine.stats().disabled, vec!["google".to_string()]);
}

#[test]
fn query_type_scope() {
    let engine = SafeSearchEngine::new(&enabled_config());
    for qtype in [1, 28, 65] {
        assert!(engine.lookup("www.bing.com", qtype).is_some());
    }
    for qtype in [15, 16, 2] {
        assert!(engine.lookup("www.bing.com", qtype).is_none());
    }
}

#[test]
fn every_provider_compiles() {
    let engine = SafeSearchEngine::new(&enabled_config());
    let samples = [
        ("bing", "www.bing.com"),
        ("duckduckgo", "duckduckgo.com"),
        ("ecosia", "www.ecosia.org"),
        ("google", "www.google.com"),
        ("pixabay", "pixabay.com"),
        ("yandex", "ya.ru"),
        ("youtube", "www.youtube.com"),
    ];
    for (service, domain) in samples {
        let result = engine.lookup(domain, TYPE_A).unwrap();
        assert_eq!(result.service, service);
    }
}

#[test]
fn configure_hot_swap() {
    let engine = SafeSearchEngine::new(&SafeSearchConfig::default());
    engine.configure(&enabled_config());
    assert!(engine.lookup("www.google.com", TYPE_A).is_some());
    engine.configure(&SafeSearchConfig {
        enabled: false,
        ..SafeSearchConfig::default()
    });
    assert!(engine.lookup("www.google.com", TYPE_A).is_none());
}

#[test]
fn rule_line_parser_tolerates_comments_and_rejects_bad_values() {
    assert!(parse_rule_line("", "google").is_none());
    assert!(parse_rule_line("! comment", "google").is_none());
    assert!(parse_rule_line("# comment", "google").is_none());
    assert!(parse_rule_line("|www.google.com^$dnsrewrite=NOERROR;CNAME;", "google").is_none());
    assert!(parse_rule_line("|www.google.com^$dnsrewrite=NOERROR;BOGUS;value", "google").is_none());

    let (domain, rule) = parse_rule_line(
        "|www.google.com^$dnsrewrite=noerror;CNAME;ForceSafeSearch.Google.com",
        "google",
    )
    .unwrap();
    assert_eq!(domain, "www.google.com");
    assert_eq!(rule.cname, "forcesafesearch.google.com.");
}

#[test]
fn ttl_defaults_when_zero() {
    let engine = SafeSearchEngine::new(&enabled_config());
    assert_eq!(engine.stats().ttl, 300);
    let engine = SafeSearchEngine::new(&SafeSearchConfig {
        enabled: true,
        disabled: Vec::new(),
        ttl: 42,
    });
    assert_eq!(engine.stats().ttl, 42);
}

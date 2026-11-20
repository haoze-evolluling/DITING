use super::*;
use diting_desktop_api::config::RewriteRecord;

fn rule(domain: &str, ips: &[&str]) -> RewriteRule {
    RewriteRule {
        domain: domain.to_string(),
        ips: ips.iter().map(|ip| ip.to_string()).collect(),
        ..RewriteRule::default()
    }
}

#[test]
fn exact_and_wildcard_lookups() {
    let engine = RewriteEngine::new(&RewriteConfig {
        enabled: true,
        ttl: 120,
        rules: vec![
            rule("nas.lan", &["192.168.1.100"]),
            rule("*.test", &["127.0.0.1"]),
        ],
    });
    let result = engine.lookup("nas.lan", 1);
    assert!(result.matched);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(result.answers[0].ttl, 120);

    assert!(engine.lookup("api.test", 1).matched);
    assert!(!engine.lookup("api.other", 1).matched);
    let nodata = engine.lookup("nas.lan", 15);
    assert!(nodata.matched);
    assert!(nodata.answers.is_empty());
}

#[test]
fn records_are_converted_to_kernel_specs() {
    let engine = RewriteEngine::new(&RewriteConfig {
        enabled: true,
        ttl: 60,
        rules: vec![RewriteRule {
            domain: "mail.lan".to_string(),
            records: vec![RewriteRecord {
                kind: "MX".to_string(),
                value: "32 example.mail".to_string(),
            }],
            ..RewriteRule::default()
        }],
    });
    let result = engine.lookup("mail.lan", 15);
    assert!(result.matched);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(result.answers[0].record.rrtype(), 15);
}

#[test]
fn add_replaces_same_domain_and_delete_errors_when_missing() {
    let engine = RewriteEngine::new(&RewriteConfig::default());
    assert_eq!(engine.stats().rule_count, 0);

    engine.add_rule(rule("dynamic.dev", &["10.0.0.1"])).unwrap();
    engine.add_rule(rule("dynamic.dev", &["10.0.0.2"])).unwrap();
    let rules = engine.rules();
    assert_eq!(rules.len(), 1);
    assert_eq!(rules[0].ips, vec!["10.0.0.2"]);

    let result = engine.lookup("dynamic.dev", 1);
    assert_eq!(result.answers.len(), 1);

    engine.delete_rule("dynamic.dev").unwrap();
    assert!(!engine.lookup("dynamic.dev", 1).matched);
    assert!(engine.delete_rule("dynamic.dev").is_err());
    assert!(engine.add_rule(rule("   ", &[])).is_err());
}

#[test]
fn set_rules_drops_empty_domains_and_keeps_config() {
    let engine = RewriteEngine::new(&RewriteConfig {
        enabled: true,
        ttl: 0,
        rules: vec![rule("keep.lan", &["10.0.0.1"]), rule(" . ", &["10.0.0.2"])],
    });
    assert_eq!(engine.rules().len(), 1);

    engine.set_rules(vec![rule("next.lan", &["10.0.0.3"])]);
    assert_eq!(engine.rules().len(), 1);
    assert!(engine.lookup("next.lan", 1).matched);
    assert!(!engine.lookup("keep.lan", 1).matched);
}

#[test]
fn ptr_lookup_returns_every_alias() {
    let engine = RewriteEngine::new(&RewriteConfig {
        enabled: true,
        ttl: 60,
        rules: vec![
            rule("nas.lan", &["192.168.1.50"]),
            rule("storage.lan", &["192.168.1.50"]),
        ],
    });
    let names = engine.lookup_ptr("192.168.1.50".parse().unwrap());
    assert_eq!(names, vec!["nas.lan.", "storage.lan."]);
    let names = engine.lookup_ptr("::ffff:192.168.1.50".parse().unwrap());
    assert_eq!(names, vec!["nas.lan.", "storage.lan."]);
    assert!(engine
        .lookup_ptr("192.168.1.51".parse().unwrap())
        .is_empty());
}

#[test]
fn disabled_engine_does_not_answer() {
    let engine = RewriteEngine::new(&RewriteConfig {
        enabled: false,
        ttl: 60,
        rules: vec![rule("nas.lan", &["10.0.0.1"])],
    });
    assert!(!engine.lookup("nas.lan", 1).matched);
    assert!(engine.lookup_ptr("10.0.0.1".parse().unwrap()).is_empty());
}

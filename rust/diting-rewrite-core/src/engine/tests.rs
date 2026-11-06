//! The vectors the Go tests (`rewrite_test.go` / `rewrite_records_test.go`) pin, run directly on
//! the engine.

use super::*;

fn rule(domain: &str) -> RuleConfig {
    RuleConfig {
        domain: domain.to_string(),
        ips: Vec::new(),
        cname: String::new(),
        txt: Vec::new(),
        ttl: 0,
        records: Vec::new(),
        rcode: String::new(),
    }
}

fn engine(rules: Vec<RuleConfig>) -> Engine {
    let (engine, warnings) = Engine::build(&Config {
        enabled: true,
        default_ttl: DEFAULT_TTL,
        rules,
    });
    assert!(warnings.is_empty(), "{warnings:?}");
    engine
}

fn a_addresses(answers: &[Answer]) -> Vec<[u8; 4]> {
    answers
        .iter()
        .filter_map(|answer| match answer.record {
            Record::A(address) => Some(address),
            _ => None,
        })
        .collect()
}

#[test]
fn exact_rules_answer_by_query_type() {
    let mut nas = rule("nas.lan");
    nas.ips = vec!["192.168.1.100".to_string(), "fe80::1".to_string()];
    nas.ttl = 120;
    let engine = engine(vec![nas]);

    let result = engine.lookup("nas.lan.", TYPE_A);
    assert!(result.matched);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(result.answers[0].owner, "nas.lan.");
    assert_eq!(result.answers[0].ttl, 120);
    assert_eq!(result.answers[0].record, Record::A([192, 168, 1, 100]));

    let result = engine.lookup("nas.lan", TYPE_AAAA);
    assert!(result.matched);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(
        result.answers[0].record,
        Record::Aaaa([0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    );

    // A matched rule without a record of the query type is authoritative NODATA.
    let result = engine.lookup("nas.lan", 15);
    assert!(result.matched);
    assert!(result.answers.is_empty());
    assert_eq!(result.rcode, RCODE_SUCCESS);
}

#[test]
fn wildcards_match_by_longest_suffix_and_keep_configuration_order() {
    let mut wide = rule("*.lan");
    wide.ips = vec!["10.0.0.1".to_string()];
    let mut corp = rule("*.corp.lan");
    corp.ips = vec!["10.0.0.2".to_string()];
    let mut deep = rule("*.deep.sub.corp.lan");
    deep.ips = vec!["10.0.0.3".to_string()];
    let engine = engine(vec![wide, corp, deep]);

    assert_eq!(
        a_addresses(&engine.lookup("my.deep.sub.corp.lan", TYPE_A).answers),
        vec![[10, 0, 0, 3]]
    );
    assert_eq!(
        a_addresses(&engine.lookup("my.corp.lan", TYPE_A).answers),
        vec![[10, 0, 0, 2]]
    );
    assert_eq!(
        a_addresses(&engine.lookup("my.lan", TYPE_A).answers),
        vec![[10, 0, 0, 1]]
    );
    // The wildcard also matches its own suffix, like the old `norm == w.suffix` branch.
    assert_eq!(
        a_addresses(&engine.lookup("lan", TYPE_A).answers),
        vec![[10, 0, 0, 1]]
    );
}

#[test]
fn shortcut_cname_chains_and_stops_on_loops() {
    let mut alias1 = rule("alias1.lan");
    alias1.cname = "alias2.lan".to_string();
    let mut alias2 = rule("alias2.lan");
    alias2.cname = "target.lan".to_string();
    let mut target = rule("target.lan");
    target.ips = vec!["192.168.8.8".to_string()];
    let mut loop1 = rule("loop1.lan");
    loop1.cname = "loop2.lan".to_string();
    let mut loop2 = rule("loop2.lan");
    loop2.cname = "loop1.lan".to_string();
    let engine = engine(vec![alias1, alias2, target, loop1, loop2]);

    let result = engine.lookup("alias1.lan", TYPE_A);
    assert_eq!(result.answers.len(), 3);
    assert_eq!(
        result.answers[0].record,
        Record::Cname("alias2.lan.".to_string())
    );
    assert_eq!(
        result.answers[1].record,
        Record::Cname("target.lan.".to_string())
    );
    assert_eq!(result.answers[2].record, Record::A([192, 168, 8, 8]));
    assert_eq!(result.answers[2].owner, "target.lan.");

    let result = engine.lookup("loop1.lan", TYPE_A);
    assert!(result.matched);
    assert!(!result.answers.is_empty());

    // A CNAME query gets the alias without chasing.
    let result = engine.lookup("alias1.lan", TYPE_CNAME);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(
        result.answers[0].record,
        Record::Cname("alias2.lan.".to_string())
    );
}

#[test]
fn shortcut_txt_is_one_record_with_every_string() {
    let mut meta = rule("meta.lan");
    meta.txt = vec!["v=spf1 ~all".to_string(), "status=ok".to_string()];
    let engine = engine(vec![meta]);

    let result = engine.lookup("meta.lan", TYPE_TXT);
    assert_eq!(
        result.answers[0].record,
        Record::Txt(vec!["v=spf1 ~all".to_string(), "status=ok".to_string()])
    );
}

#[test]
fn explicit_records_are_filtered_by_query_type_and_cname_wins_its_owner() {
    let mut mail = rule("mail.lan");
    mail.records = vec![RecordSpec {
        type_name: "MX".to_string(),
        value: "32 example.mail".to_string(),
    }];
    let mut dual = rule("dual.lan");
    dual.records = vec![
        RecordSpec {
            type_name: "CNAME".to_string(),
            value: "final.lan.".to_string(),
        },
        RecordSpec {
            type_name: "A".to_string(),
            value: "10.1.2.3".to_string(),
        },
    ];
    let mut mixed = rule("mixed.lan");
    mixed.records = vec![
        RecordSpec {
            type_name: "MX".to_string(),
            value: "not-a-preference example.mail".to_string(),
        },
        RecordSpec {
            type_name: "A".to_string(),
            value: "10.0.0.1".to_string(),
        },
        RecordSpec {
            type_name: "BOGUS".to_string(),
            value: "whatever".to_string(),
        },
    ];
    let (engine, warnings) = Engine::build(&Config {
        enabled: true,
        default_ttl: 60,
        rules: vec![mail, dual, mixed],
    });
    assert_eq!(warnings.len(), 2, "{warnings:?}");

    let result = engine.lookup("mail.lan", 15);
    assert_eq!(
        result.answers[0].record,
        Record::Mx {
            preference: 32,
            exchange: "example.mail.".to_string()
        }
    );
    assert!(engine.lookup("mail.lan", 33).answers.is_empty());

    let result = engine.lookup("dual.lan", TYPE_A);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(
        result.answers[0].record,
        Record::Cname("final.lan.".to_string())
    );

    // Only the legal A record survives the compile pass.
    let result = engine.lookup("mixed.lan", TYPE_A);
    assert_eq!(result.answers.len(), 1);
    assert_eq!(result.answers[0].record, Record::A([10, 0, 0, 1]));
}

#[test]
fn rcode_overrides_the_answer_and_unknown_names_fall_back() {
    let mut gone = rule("gone.lan");
    gone.rcode = "NXDOMAIN".to_string();
    let mut deny = rule("deny.lan");
    deny.rcode = "REFUSED".to_string();
    deny.ips = vec!["10.0.0.1".to_string()];
    let mut typo = rule("typo.lan");
    typo.rcode = "NOTARCODE".to_string();
    typo.ips = vec!["10.0.0.1".to_string()];
    let (engine, warnings) = Engine::build(&Config {
        enabled: true,
        default_ttl: 60,
        rules: vec![gone, deny, typo],
    });
    assert_eq!(warnings.len(), 1, "{warnings:?}");

    let result = engine.lookup("gone.lan", TYPE_A);
    assert!(result.matched);
    assert_eq!(result.rcode, 3);
    assert!(result.answers.is_empty());

    let result = engine.lookup("deny.lan", TYPE_A);
    assert_eq!(result.rcode, 5);
    assert!(result.answers.is_empty());

    // A typo keeps the rule alive with NOERROR.
    let result = engine.lookup("typo.lan", TYPE_A);
    assert_eq!(result.rcode, RCODE_SUCCESS);
    assert_eq!(result.answers.len(), 1);
}

#[test]
fn ptr_map_covers_exact_rules_only_and_keeps_aliases() {
    let mut nas = rule("nas.lan");
    nas.ips = vec!["192.168.1.50".to_string(), "fe80::1".to_string()];
    let mut storage = rule("storage.lan");
    storage.ips = vec!["192.168.1.50".to_string()];
    let mut wildcard = rule("*.wild.lan");
    wildcard.ips = vec!["192.168.1.51".to_string()];
    let engine = engine(vec![nas, storage, wildcard]);

    assert_eq!(
        engine.lookup_ptr(&[192, 168, 1, 50]),
        vec!["nas.lan.".to_string(), "storage.lan.".to_string()]
    );
    assert_eq!(engine.lookup_reverse(&[192, 168, 1, 50]), "nas.lan");
    assert_eq!(
        engine.lookup_ptr(&[0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
        vec!["nas.lan.".to_string()]
    );
    assert_eq!(engine.lookup_ptr(&[192, 168, 1, 51]), Vec::<String>::new());
    assert_eq!(engine.lookup_ptr(&[1, 2, 3]), Vec::<String>::new());
    assert_eq!(engine.lookup_reverse(&[192, 168, 1, 99]), "");
}

#[test]
fn a_disabled_engine_never_matches() {
    let mut host = rule("host.lan");
    host.ips = vec!["10.0.0.1".to_string()];
    let (engine, _) = Engine::build(&Config {
        enabled: false,
        default_ttl: 60,
        rules: vec![host],
    });
    assert!(!engine.lookup("host.lan", TYPE_A).matched);
    assert!(engine.lookup_ptr(&[10, 0, 0, 1]).is_empty());
    assert_eq!(engine.lookup_reverse(&[10, 0, 0, 1]), "");
}

#[test]
fn exact_duplicates_use_the_last_rule() {
    let mut first = rule("dup.lan");
    first.ips = vec!["10.0.0.1".to_string()];
    let mut second = rule("dup.lan");
    second.ips = vec!["10.0.0.2".to_string()];
    let engine = engine(vec![first, second]);
    assert_eq!(
        a_addresses(&engine.lookup("dup.lan", TYPE_A).answers),
        vec![[10, 0, 0, 2]]
    );
}

#[test]
fn rule_ttl_zero_falls_back_to_the_engine_default() {
    let mut host = rule("host.lan");
    host.ips = vec!["10.0.0.1".to_string()];
    let (engine, _) = Engine::build(&Config {
        enabled: true,
        default_ttl: 300,
        rules: vec![host],
    });
    assert_eq!(engine.lookup("host.lan", TYPE_A).answers[0].ttl, 300);
    assert_eq!(engine.default_ttl(), 300);
}

#[test]
fn domains_are_normalized_like_the_go_engine() {
    assert_eq!(normalize_domain("  MyHost.LAN.  "), "myhost.lan");
    assert_eq!(normalize_domain("*.Example.COM."), "*.example.com");
    assert_eq!(normalize_domain(" . "), "");
    assert_eq!(query_fqdn("host.lan"), "host.lan.");
    assert_eq!(query_fqdn("host.lan."), "host.lan.");
}

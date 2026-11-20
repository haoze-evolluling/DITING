use super::*;
use diting_desktop_api::config::ZoneEntry;

fn entry(id: &str, origin: &str, content: &str) -> ZoneEntry {
    ZoneEntry {
        id: id.to_string(),
        origin: origin.to_string(),
        content: content.to_string(),
        enabled: true,
    }
}

fn make_engine(ttl: u32, zones: Vec<ZoneEntry>) -> ZoneEngine {
    ZoneEngine::new(&ZoneConfig {
        enabled: true,
        ttl,
        zones,
    })
}

#[test]
fn basic_lookup_and_default_ttl() {
    let engine = make_engine(
        77,
        vec![entry(
            "z1",
            "lan",
            "$ORIGIN lan.\n@ IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)\n@ IN NS ns.lan.\nwww IN A 10.0.0.10\nwww IN A 10.0.0.11\nv6 IN AAAA 2001:db8::1\n",
        )],
    );
    assert!(engine.enabled());
    let answer = engine.lookup("www.lan.", 1);
    assert!(answer.matched);
    assert_eq!(answer.rcode, 0);
    assert_eq!(answer.answers.len(), 2);
    assert_eq!(answer.answers[0].ttl, 77);
    assert!(answer.authority.is_empty());

    let answer = engine.lookup("v6.lan", 28);
    assert_eq!(answer.answers.len(), 1);
    assert_eq!(
        answer.answers[0].rdata,
        ZoneRData::Aaaa("2001:db8::1".parse().unwrap())
    );
}

#[test]
fn nodata_and_nxdomain_carry_soa() {
    let engine = make_engine(
        300,
        vec![entry(
            "z1",
            "lan",
            "$ORIGIN lan.\n@ IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)\nwww IN A 10.0.0.10\n",
        )],
    );
    let nodata = engine.lookup("www.lan.", 28);
    assert!(nodata.matched);
    assert_eq!(nodata.rcode, 0);
    assert!(nodata.answers.is_empty());
    assert_eq!(nodata.authority.len(), 1);
    assert_eq!(nodata.authority[0].rtype, TYPE_SOA);

    let absent = engine.lookup("nothing.lan.", 1);
    assert!(absent.matched);
    assert_eq!(absent.rcode, RCODE_NXDOMAIN);
    assert!(absent.answers.is_empty());
    assert_eq!(absent.authority.len(), 1);

    assert!(!engine.lookup("example.com.", 1).matched);
}

#[test]
fn explicit_ttl_wins() {
    let engine = make_engine(77, vec![entry("z1", "lan", "www 600 IN A 10.0.0.1\n")]);
    assert_eq!(engine.lookup("www.lan.", 1).answers[0].ttl, 600);
}

#[test]
fn cname_chain_is_followed() {
    let engine = make_engine(
        300,
        vec![entry(
            "z1",
            "lan",
            "$ORIGIN lan.\nalias IN CNAME real\nalias2 IN CNAME alias\nreal IN A 10.0.0.9\n",
        )],
    );
    let answer = engine.lookup("alias2.lan.", 1);
    assert!(answer.matched);
    assert_eq!(answer.answers.len(), 3);
    assert_eq!(answer.answers[0].rtype, TYPE_CNAME);
    assert_eq!(answer.answers[2].rtype, 1);

    let missing = engine.lookup("alias.lan.", 28);
    assert!(missing.matched);
    assert!(missing.answers.is_empty());
    assert_eq!(missing.authority.len(), 1);
}

#[test]
fn longest_origin_wins() {
    let engine = make_engine(
        300,
        vec![
            entry("outer", "lan", "www A 10.0.0.1\n"),
            entry("inner", "corp.lan", "www A 10.0.0.2\n"),
        ],
    );
    let answer = engine.lookup("www.corp.lan.", 1);
    assert_eq!(
        answer.answers[0].rdata,
        ZoneRData::A("10.0.0.2".parse().unwrap())
    );
}

#[test]
fn disabled_zones_and_global_switch() {
    let mut off = entry("off", "corp", "www A 10.0.0.2\n");
    off.enabled = false;
    let engine = make_engine(300, vec![entry("on", "lan", "www A 10.0.0.1\n"), off]);
    assert!(engine.lookup("www.lan.", 1).matched);
    assert!(!engine.lookup("www.corp.", 1).matched);
    let states = engine.states();
    assert_eq!(states.len(), 2);
    assert!(states[0].loaded);
    assert!(!states[1].loaded);

    let disabled = ZoneEngine::new(&ZoneConfig {
        enabled: false,
        ttl: 300,
        zones: vec![entry("z", "lan", "www A 10.0.0.1\n")],
    });
    assert!(!disabled.enabled());
    assert!(!disabled.lookup("www.lan.", 1).matched);
}

#[test]
fn include_and_invalid_text_fail_the_zone() {
    let engine = make_engine(
        300,
        vec![entry(
            "z1",
            "lan",
            "$INCLUDE /etc/passwd\nwww IN A 10.0.0.1\n",
        )],
    );
    let states = engine.states();
    assert_eq!(states.len(), 1);
    assert!(!states[0].loaded);
    assert!(states[0].error.as_deref().unwrap().contains("INCLUDE"));
    assert!(!engine.lookup("www.lan.", 1).matched);
}

#[test]
fn content_and_record_limits() {
    let oversized = "; pad\n".repeat(MAX_ZONE_CONTENT_BYTES / 6 + 2);
    let engine = make_engine(300, vec![entry("z1", "lan", &oversized)]);
    let states = engine.states();
    assert!(!states[0].loaded);
    assert!(states[0].error.as_deref().unwrap().contains("超出上限"));

    let engine = make_engine(
        300,
        vec![entry(
            "z1",
            "lan",
            "$GENERATE 1-50000 host$ IN A 10.0.0.1\n",
        )],
    );
    let states = engine.states();
    assert!(states[0].loaded);
    assert_eq!(states[0].records, MAX_ZONE_RECORDS);
    assert!(states[0].error.as_deref().unwrap().contains("截断"));
}

#[test]
fn zone_count_limit() {
    let zones: Vec<ZoneEntry> = (0..MAX_ZONE_COUNT + 2)
        .map(|index| entry("z", &format!("z{index}.lan"), "www A 10.0.0.1\n"))
        .collect();
    let engine = make_engine(300, zones);
    let states = engine.states();
    assert_eq!(states.len(), MAX_ZONE_COUNT + 2);
    assert!(states[MAX_ZONE_COUNT - 1].loaded);
    assert!(!states[MAX_ZONE_COUNT].loaded);
}

#[test]
fn configure_rebuilds_and_clears_old_records() {
    let engine = make_engine(300, vec![entry("z1", "lan", "www A 10.0.0.1\n")]);
    assert!(engine.lookup("www.lan.", 1).matched);
    engine.configure(&ZoneConfig {
        enabled: true,
        ttl: 0,
        zones: Vec::new(),
    });
    assert!(!engine.lookup("www.lan.", 1).matched);
    assert_eq!(engine.default_ttl(), 300);
}

#[test]
fn any_returns_every_type() {
    let engine = make_engine(
        300,
        vec![entry(
            "z1",
            "lan",
            "www A 10.0.0.1\nwww AAAA 2001:db8::1\nwww TXT \"hello\"\n",
        )],
    );
    let answer = engine.lookup("www.lan.", TYPE_ANY);
    assert_eq!(answer.answers.len(), 3);
}

#[test]
fn synthetic_soa_used_when_zone_declares_none() {
    let engine = make_engine(120, vec![entry("z1", "lan", "www A 10.0.0.1\n")]);
    let answer = engine.lookup("missing.lan.", 1);
    let soa = &answer.authority[0];
    assert_eq!(soa.rtype, TYPE_SOA);
    assert_eq!(soa.ttl, 120);
    match &soa.rdata {
        ZoneRData::Soa { minimum, .. } => assert_eq!(*minimum, 120),
        other => panic!("unexpected SOA body: {other:?}"),
    }
}

//! The vectors the Go tests (`rewrite_records_test.go`) and the old `buildRewriteRR` branches pin.

use super::*;

/// Builds a record and unwraps it; `qtype` defaults to the record's own type when `None`.
fn record_of(type_name: &str, value: &str) -> Record {
    let code = lookup_type(type_name).expect("the type is supported");
    build("host.lan", code, type_name, value, 60)
        .expect("the value is legal")
        .expect("the record answers its own query type")
        .record
}

fn rejection(type_name: &str, value: &str) -> String {
    let code = lookup_type(type_name).expect("the type is supported");
    build("host.lan", code, type_name, value, 60).expect_err("the value must be rejected")
}

#[test]
fn mx_and_srv_split_their_fields() {
    assert_eq!(
        record_of("MX", "32 example.mail"),
        Record::Mx {
            preference: 32,
            exchange: "example.mail.".to_string()
        }
    );
    assert_eq!(
        record_of("SRV", "10 60 8080 sip.lan"),
        Record::Srv {
            priority: 10,
            weight: 60,
            port: 8080,
            target: "sip.lan.".to_string()
        }
    );
    // Fields are split like `strings.Fields`, so extra whitespace is not a field.
    assert_eq!(
        record_of("MX", "  32   example.mail "),
        Record::Mx {
            preference: 32,
            exchange: "example.mail.".to_string()
        }
    );
    assert!(rejection("MX", "not-a-preference example.mail").contains("MX 优先级无效"));
    assert!(rejection("MX", "32").contains("两个字段"));
    assert!(rejection("SRV", "10 60 8080").contains("四个字段"));
    assert!(rejection("SRV", "10 60 70000 sip.lan").contains("SRV 端口无效"));
}

#[test]
fn name_targets_are_validated_and_qualified() {
    assert_eq!(
        record_of("NS", "ns1.delegated.lan"),
        Record::Ns("ns1.delegated.lan.".to_string())
    );
    assert_eq!(
        record_of("PTR", "host.example."),
        Record::Ptr("host.example.".to_string())
    );
    assert_eq!(
        record_of("CNAME", "target.example.com"),
        Record::Cname("target.example.com.".to_string())
    );
    // Single-label intranet hostnames are legal targets.
    assert_eq!(record_of("CNAME", "nas"), Record::Cname("nas.".to_string()));
    // An IP address is not a target name.
    assert!(rejection("CNAME", "10.0.0.1").contains("不是合法的域名"));
    assert!(rejection("NS", "").contains("不是合法的域名"));
}

#[test]
fn txt_keeps_its_text_and_needs_one() {
    assert_eq!(
        record_of("TXT", "v=spf1 ~all"),
        Record::Txt("v=spf1 ~all".to_string())
    );
    assert_eq!(
        record_of("TXT", "  padded  "),
        Record::Txt("padded".to_string())
    );
    assert_eq!(rejection("TXT", "   "), "TXT 记录缺少取值");
}

#[test]
fn addresses_are_typed_and_aaaa_rejects_ipv4() {
    assert_eq!(record_of("A", "10.1.2.3"), Record::A([10, 1, 2, 3]));
    // An IPv4-mapped IPv6 literal is an IPv4 address for `To4`.
    assert_eq!(record_of("A", "::ffff:10.1.2.3"), Record::A([10, 1, 2, 3]));
    assert_eq!(
        record_of("AAAA", "fe80::1"),
        Record::Aaaa([0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    );
    // The IPv4 literal must not become `::ffff:10.0.0.5`.
    assert!(rejection("AAAA", "10.0.0.5").contains("不是合法的 IPv6 地址"));
    assert!(rejection("A", "::1.2.3.4").contains("不是合法的 IPv4 地址"));
    assert!(rejection("A", "10.0.0.256").contains("不是合法的 IPv4 地址"));
}

#[test]
fn https_parses_every_supported_parameter() {
    let record = record_of(
        "HTTPS",
        "1 . alpn=h3,h2 port=8443 ipv4hint=10.0.0.9 ipv6hint=2001:db8::1 dohpath=/dns-query{?dns}",
    );
    let Record::Svcb {
        https,
        priority,
        target,
        params,
    } = record
    else {
        panic!("expected an SVCB record, got {record:?}");
    };
    assert!(https);
    assert_eq!(priority, 1);
    // `.` means the query name itself.
    assert_eq!(target, ".");
    assert_eq!(
        params,
        vec![
            SvcParam::Alpn(vec!["h3".to_string(), "h2".to_string()]),
            SvcParam::Port(8443),
            SvcParam::Ipv4Hint(vec![[10, 0, 0, 9]]),
            SvcParam::Ipv6Hint(vec![[
                0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
            ]]),
            SvcParam::DoHPath("/dns-query{?dns}".to_string()),
        ]
    );

    let record = record_of(
        "SVCB",
        "1 svc.example. alpn=h3 no-default-alpn mandatory=alpn,port",
    );
    let Record::Svcb { https, params, .. } = record else {
        panic!("expected an SVCB record");
    };
    assert!(!https);
    assert_eq!(
        params,
        vec![
            SvcParam::Alpn(vec!["h3".to_string()]),
            SvcParam::NoDefaultAlpn,
            SvcParam::Mandatory(vec![SVCB_KEY_ALPN, SVCB_KEY_PORT]),
        ]
    );
}

#[test]
fn https_rejects_broken_parameters() {
    // The hints take one address, like AdGuard Home's parser.
    assert!(rejection("HTTPS", "1 . ipv4hint=1.2.3.4,5.6.7.8").contains("ipv4hint"));
    assert!(rejection("HTTPS", "1 . ipv6hint=nonsense").contains("ipv6hint"));
    assert!(rejection("HTTPS", "1 . alpn=h2 alpn=h3").contains("重复出现"));
    assert!(rejection("HTTPS", "1 . bogus=1").contains("不支持的 SVCB 参数"));
    assert!(rejection("HTTPS", "1 . port=99999").contains("port 参数无效"));
    assert!(rejection("HTTPS", "1 . alpn=").contains("缺少取值"));
    assert!(rejection("HTTPS", "1 . alpn=h3,,h2").contains("含空取值"));
    assert!(rejection("HTTPS", "1 . mandatory=bogus").contains("未知的键"));
    assert!(rejection("HTTPS", "1 . dohpath=").contains("dohpath 参数缺少取值"));
    assert!(rejection("HTTPS", "1 . ech=not-base64!").contains("Base64"));
    assert!(rejection("HTTPS", "1").contains("至少需要"));
    assert!(rejection("HTTPS", "high .").contains("SVCB 优先级无效"));
    assert!(rejection("HTTPS", "1 10.0.0.1").contains("不是合法的域名"));
    // A quoted value is unwrapped like `strings.Trim(value, "\"")` did.
    let record = record_of("HTTPS", "1 . dohpath=\"/dns-query\"");
    let Record::Svcb { params, .. } = record else {
        panic!("expected an SVCB record");
    };
    assert_eq!(params, vec![SvcParam::DoHPath("/dns-query".to_string())]);
}

#[test]
fn only_cname_answers_other_query_types() {
    // The type mismatch is the caller's `NODATA` signal.
    assert_eq!(build("host.lan", TYPE_A, "MX", "32 mail.lan", 60), Ok(None));
    assert_eq!(
        build("host.lan", TYPE_MX, "SRV", "1 2 3 target", 60),
        Ok(None)
    );
    // CNAME is a property of the name, so every query type gets it.
    for qtype in [TYPE_A, TYPE_AAAA, TYPE_MX, TYPE_CNAME, TYPE_HTTPS] {
        let record = build("host.lan", qtype, "cname", "target.example", 30).expect("legal");
        assert_eq!(
            record,
            Some(ParsedRecord {
                owner: "host.lan.".to_string(),
                ttl: 30,
                record: Record::Cname("target.example.".to_string()),
            })
        );
    }
}

#[test]
fn the_owner_name_is_qualified() {
    let owner_of = |name: &str| {
        build(name, TYPE_A, "A", "10.0.0.1", 1)
            .expect("legal")
            .expect("A answers A")
            .owner
    };
    assert_eq!(owner_of("host.lan"), "host.lan.");
    assert_eq!(owner_of("host.lan."), "host.lan.");
    assert_eq!(owner_of(""), ".");
    assert_eq!(owner_of("."), ".");
    // An escaped trailing dot is not a label separator, so the name is not absolute.
    assert_eq!(owner_of("host\\."), "host\\..");
}

#[test]
fn unknown_types_and_values_are_rejected() {
    assert!(build("host", TYPE_A, "BOGUS", "whatever", 60)
        .expect_err("unknown type")
        .contains("不支持的记录类型"));
    // A type that exists in DNS but not in the rewrite grammar, e.g. SOA.
    assert!(build("host", 6, "soa", "whatever", 60).is_err());
}

#[test]
fn the_type_list_is_sorted_and_complete() {
    assert_eq!(
        type_names(),
        ["A", "AAAA", "CNAME", "HTTPS", "MX", "NS", "PTR", "SRV", "SVCB", "TXT"]
    );
    let mut sorted: Vec<&str> = RECORD_TYPES.iter().map(|(name, _)| *name).collect();
    sorted.sort_unstable();
    assert_eq!(sorted, type_names());
    for (name, code) in RECORD_TYPES {
        assert_eq!(lookup_type(&name.to_ascii_lowercase()), Some(code));
        assert_eq!(lookup_type(&format!(" {name}\t")), Some(code));
    }
}

#[test]
fn rewrite_targets_accept_hosts_and_reject_addresses() {
    assert!(is_rewrite_target("nas"));
    assert!(is_rewrite_target("nas.lan."));
    assert!(is_rewrite_target("  spaced.lan  "));
    assert!(is_rewrite_target("bücher.example"));
    assert!(!is_rewrite_target(""));
    assert!(!is_rewrite_target("."));
    assert!(!is_rewrite_target("10.0.0.1"));
    assert!(!is_rewrite_target("fe80::1"));
    assert!(!is_rewrite_target("a..b"));
    assert!(!is_rewrite_target("under_score.lan"));
    assert!(!is_rewrite_target(&format!("{}.lan", "a".repeat(64))));
    assert!(!is_rewrite_target(&"a.".repeat(200)));
}

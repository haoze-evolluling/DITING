use super::*;
use crate::record::{TYPE_MX, TYPE_TXT};

fn parse(text: &str) -> Action {
    Action::parse(text).expect("the value is legal")
}

fn rejected(text: &str) -> String {
    Action::parse(text).expect_err("the value must be rejected")
}

#[test]
fn adguard_syntax_parses_to_one_action_each() {
    assert_eq!(
        parse("127.0.0.1"),
        Action::new(false, 0, TYPE_A, "127.0.0.1")
    );
    assert_eq!(
        parse("abcd::1234"),
        Action::new(false, 0, TYPE_AAAA, "abcd::1234")
    );
    assert_eq!(
        parse("example.org"),
        Action::new(false, 0, TYPE_CNAME, "example.org")
    );
    assert_eq!(parse("REFUSED"), Action::new(false, 5, 0, ""));
    assert_eq!(
        parse("NOERROR;TXT;hello-world"),
        Action::new(false, 0, TYPE_TXT, "hello-world")
    );
    assert_eq!(parse("NXDOMAIN;;"), Action::new(false, 3, 0, ""));
}

#[test]
fn keywords_and_fields_are_case_insensitive_and_trimmed() {
    assert_eq!(parse("refused"), Action::new(false, 5, 0, ""));
    assert_eq!(
        parse("  noerror ; txt ;  Hello World  "),
        Action::new(false, 0, TYPE_TXT, "Hello World")
    );
    assert_eq!(
        parse("::ffff:127.0.0.1"),
        Action::new(false, 0, TYPE_A, "::ffff:127.0.0.1")
    );
}

#[test]
fn explicit_nodata_differs_from_the_bare_form() {
    assert_eq!(parse("NOERROR;;"), Action::new(false, 0, 0, ""));
    assert_eq!(parse(""), Action::new(true, 0, 0, ""));
    assert_eq!(parse("   "), Action::new(true, 0, 0, ""));
}

#[test]
fn only_the_first_two_semicolons_split() {
    assert_eq!(
        parse("NOERROR;TXT;a;b;c"),
        Action::new(false, 0, TYPE_TXT, "a;b;c")
    );
    assert_eq!(
        parse("NOERROR;MX;32 mail.lan"),
        Action::new(false, 0, TYPE_MX, "32 mail.lan")
    );
}

#[test]
fn invalid_values_are_rejected() {
    assert!(rejected("NOERROR;A;not-an-ip").contains("不是合法的 IPv4 地址"));
    assert!(rejected("NOERROR;AAAA;1.2.3.4.5").contains("不是合法的 IPv6 地址"));
    assert!(rejected("NOERROR;XX;1.2.3.4").contains("未知的记录类型"));
    assert!(rejected("NOERROR;NAPTR;0 0 \"\" .").contains("不支持"));
    assert!(rejected("NOERROR;A;").contains("缺少取值"));
    assert!(rejected("not a host").contains("不是合法的域名"));
    assert!(rejected("NOERROR;CNAME;bad..host").contains("不是合法的域名"));
    assert!(rejected("BOGUS;A;1.2.3.4").contains("未知的应答码"));
}

#[test]
fn the_key_canonicalizes_addresses() {
    assert_eq!(parse("127.0.0.1").key(), "0;1;127.0.0.1");
    assert_eq!(parse("::ffff:127.0.0.1").key(), "0;1;127.0.0.1");
    assert_eq!(parse("NOERROR;A; 10.0.0.1 ").key(), "0;1;10.0.0.1");
    assert_eq!(parse("ABCD::1").key(), "0;28;abcd::1");
    assert_eq!(parse("NOERROR;AAAA;ABCD::1").key(), "0;28;abcd::1");
}

#[test]
fn the_key_canonicalizes_target_names() {
    assert_eq!(parse("Example.ORG.").key(), "0;5;example.org");
    assert_eq!(parse("example.org").key(), "0;5;example.org");
    assert_eq!(parse("NOERROR;PTR;Host.Lan.").key(), "0;12;host.lan");
    assert_eq!(parse("NOERROR;NS;Host.Lan").key(), "0;2;host.lan");
    assert_eq!(parse("NOERROR;TXT; Hello ").key(), "0;16;Hello");
}

#[test]
fn the_key_covers_bare_and_record_less_actions() {
    assert_eq!(parse("").key(), "bare");
    assert_eq!(parse("NOERROR;;").key(), "0;0;");
    assert_eq!(parse("REFUSED").key(), "5;0;");
    assert_eq!(parse("SERVFAIL;;ignored").key(), "2;0;");
}

//! Parser and table behaviour, one case per branch of the old `parseHostsReader`.

use super::*;
use crate::ip::{parse_ip, Addr};

fn build_table(text: &str) -> HostsTable {
    parse_text(text)
}

#[test]
fn parses_the_shape_of_a_hosts_file() {
    let table = build_table(
        "# comment\n\
         127.0.0.1 localhost myapp.local\n\
         192.168.1.100 nas.home storage.home # lan nas\n\
         ::1 localhost ip6-localhost\n\
         2001:db8::1 ipv6.test.local\n\
         fe80::1%eth0 linklocal.local\n",
    );
    assert_eq!(
        table.lookup("myapp.local", TYPE_A),
        vec![Addr::V4([127, 0, 0, 1])]
    );
    assert_eq!(
        table.lookup("nas.home", TYPE_A),
        vec![Addr::V4([192, 168, 1, 100])]
    );
    // The `# lan nas` comment ends the line, so those two words are not hosts.
    assert!(!table.has_domain("lan"));
    assert!(!table.has_domain("nas"));
    let mut loopback = [0u8; 16];
    loopback[15] = 1;
    assert_eq!(
        table.lookup("ip6-localhost", TYPE_AAAA),
        vec![Addr::V6(loopback)]
    );
    // The interface zone is cut, so this is fe80::1 and not a parse failure.
    assert_eq!(
        table.lookup("linklocal.local", TYPE_AAAA),
        vec![parse_ip("fe80::1").unwrap()]
    );
}

#[test]
fn normalizes_hosts_and_queries() {
    let table = build_table("  192.168.1.101  Dotted.Host.  dotted.host\n");
    assert!(table.has_domain("dotted.host"));
    assert!(table.has_domain(".DOTTED.HOST."));
    assert_eq!(
        table.lookup("DOTTED.host", TYPE_A),
        vec![Addr::V4([192, 168, 1, 101])]
    );
    // Both spellings fold to one host, and the duplicate address is stored once.
    assert_eq!(
        table.ptr("101.1.168.192.in-addr.arpa."),
        vec!["dotted.host".to_string()]
    );
    // A host that is only dots normalizes to the empty string and is skipped.
    assert!(!table.has_domain("..."));
    assert!(!table.has_domain("."));
}

#[test]
fn folds_hosts_like_go_not_like_rust() {
    // `strings.ToLower` maps U+0130 to a plain `i`; Rust's full mapping would produce `i` + U+0307.
    let table = build_table("127.0.0.1 \u{0130}stanbul.test\n");
    assert!(table.has_domain("\u{0130}stanbul.test"));
    assert!(!table.has_domain("i\u{0307}stanbul.test"));
    // Non-ASCII hosts that are already lowercase keep working.
    let table = build_table("127.0.0.1 \u{00e4}\u{00f6}\u{00fc}.test\n");
    assert!(table.has_domain("\u{00c4}\u{00d6}\u{00dc}.test"));
}

#[test]
fn skips_lines_without_a_usable_address_or_host() {
    let table = build_table(
        "not-an-ip host.without.ip\n\
         10.0.0.1\n\
         010.0.0.1 leading.zero\n\
         0x7f.0.0.1 hex.ip\n\
         10.1.1.4 a#b\n\
         10.1.1.5 .\n\
         #\n\
         \n",
    );
    assert!(!table.has_domain("host.without.ip"));
    assert!(!table.has_domain("leading.zero"));
    assert!(!table.has_domain("hex.ip"));
    // `a#b` is `a` plus a comment, so `a` is the host.
    assert_eq!(table.lookup("a", TYPE_A), vec![Addr::V4([10, 1, 1, 4])]);
    assert!(!table.has_domain("b"));
}

#[test]
fn keeps_duplicates_out_and_order_in() {
    let table = build_table(
        "127.0.0.1 first.host\n\
         127.0.0.1 first.host\n\
         127.0.0.2 second.host\n\
         127.0.0.1 alias.host\n",
    );
    assert_eq!(
        table.lookup("first.host", TYPE_A),
        vec![Addr::V4([127, 0, 0, 1])]
    );
    assert_eq!(
        table.ptr("1.0.0.127.in-addr.arpa."),
        vec!["first.host".to_string(), "alias.host".to_string()]
    );
    assert_eq!(table.reverse(&Addr::V4([127, 0, 0, 1])), Some("first.host"));
    assert_eq!(table.reverse(&Addr::V4([127, 0, 0, 9])), None);
}

#[test]
fn collapses_the_mapped_form_and_reads_it_back() {
    let table =
        build_table("::ffff:192.168.1.100 mapped.home\n0:0:0:0:0:ffff:1.2.3.4 hex.mapped\n");
    assert_eq!(
        table.lookup("mapped.home", TYPE_A),
        vec![Addr::V4([192, 168, 1, 100])]
    );
    assert_eq!(table.lookup("mapped.home", TYPE_AAAA), Vec::new());
    assert_eq!(
        table.lookup("hex.mapped", TYPE_A),
        vec![Addr::V4([1, 2, 3, 4])]
    );
    // The reverse name of the IPv4 form finds the alias, which is what the old string key did too.
    assert_eq!(
        table.ptr("100.1.168.192.in-addr.arpa."),
        vec!["mapped.home".to_string()]
    );
}

#[test]
fn answers_only_the_asked_family() {
    let table = build_table("127.0.0.1 both.host\n::1 both.host\n");
    assert_eq!(
        table.lookup("both.host", TYPE_A),
        vec![Addr::V4([127, 0, 0, 1])]
    );
    assert_eq!(
        table.lookup("both.host", TYPE_AAAA),
        vec![parse_ip("::1").unwrap()]
    );
    // Any other qtype has no hosts answer; the Go middleware only asks A / AAAA.
    assert_eq!(table.lookup("both.host", 16), Vec::new());
    assert!(table.has_domain("both.host"));
    assert!(!table.has_domain("other.host"));
}

#[test]
fn garbage_reverse_names_are_misses() {
    let table = build_table("127.0.0.1 localhost\n");
    assert!(table.ptr("example.com.").is_empty());
    assert!(table.ptr("").is_empty());
    assert!(table.ptr("1.2.3.in-addr.arpa.").is_empty());
    assert_eq!(
        table.ptr("1.0.0.127.in-addr.arpa."),
        vec!["localhost".to_string()]
    );
}

#[test]
fn a_line_past_the_scanner_limit_ends_the_file() {
    // `bufio.Scanner` gives up for good on a token over 64 KiB, so nothing after it is parsed —
    // including the lines that would have been fine on their own.
    let text = format!(
        "10.9.9.8 before.big\n{}\n10.9.9.9 after.big\n",
        "x".repeat(70000)
    );
    let table = build_table(&text);
    assert!(table.has_domain("before.big"));
    assert!(!table.has_domain("after.big"));
    // A line that fits exactly is still parseable.
    let padding = format!("#{}\n10.9.9.7 fits.host\n", "x".repeat(MAX_LINE_BYTES - 2));
    let table = build_table(&padding);
    assert!(table.has_domain("fits.host"));
}

#[test]
fn reads_files_and_remembers_what_worked() {
    let dir = std::env::temp_dir().join(format!("diting-hosts-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temp dir");
    let good = dir.join("good.hosts");
    std::fs::write(&good, "10.0.0.1 file.host\n").expect("write");
    let missing = dir.join("missing.hosts");

    let table = HostsTable::build(&[
        Source::File(good.clone()),
        Source::File(missing.clone()),
        Source::Text("10.0.0.2 text.host\n".to_string()),
    ]);
    assert_eq!(table.loaded(), &[good.display().to_string()]);
    assert!(table
        .error()
        .expect("an error")
        .starts_with(&missing.display().to_string()));
    assert!(table.has_domain("file.host"));
    assert!(table.has_domain("text.host"));

    let clean = HostsTable::build(&[Source::Text("10.0.0.3 clean.host\n".to_string())]);
    assert!(clean.error().is_none());
    assert!(clean.loaded().is_empty());

    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn an_empty_source_list_is_an_empty_table() {
    let table = HostsTable::build(&[]);
    assert!(!table.has_domain("anything"));
    assert!(table.ptr("1.0.0.127.in-addr.arpa.").is_empty());
    assert!(table.reverse(&Addr::V4([127, 0, 0, 1])).is_none());
    assert!(table.loaded().is_empty());
}

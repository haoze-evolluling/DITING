use super::*;

fn entry(domain: &str, targets: &[&str]) -> (String, Vec<String>) {
    (
        domain.to_string(),
        targets.iter().map(|target| target.to_string()).collect(),
    )
}

#[test]
fn build_normalizes_keys_and_drops_blanks() {
    let table = RewriteTable::build(&[
        entry("GitHub.COM.", &["140.82.112.3"]),
        entry("  ", &["1.1.1.1"]),
        entry("empty.example", &["   "]),
        entry("bad.example", &[]),
    ]);
    assert_eq!(table.len(), 1);
    assert!(table.lookup("www.github.com").is_some());
    assert!(table.lookup("empty.example").is_none());
}

#[test]
fn lookup_walks_parent_suffixes() {
    let table = RewriteTable::build(&[
        entry("example.com", &["1.2.3.4", "::1", "Target.Example."]),
        entry("com", &["9.9.9.9"]),
    ]);
    let exact = table.lookup("example.com").expect("exact");
    assert_eq!(exact.ip4, "1.2.3.4");
    assert_eq!(exact.ip6, "::1");
    assert_eq!(exact.cname, "target.example");

    let child = table.lookup("WWW.Example.COM").expect("child");
    assert_eq!(child.ip4, "1.2.3.4");

    // The tld entry only applies once the longer suffix misses.
    let parent = table.lookup("other.com").expect("parent");
    assert_eq!(parent.ip4, "9.9.9.9");
    assert_eq!(table.lookup("notgithub.com").expect("tld").ip4, "9.9.9.9");
    assert!(table.lookup(".").is_none());
    assert!(RewriteTable::build(&[entry("example.com", &["1.2.3.4"])])
        .lookup("notexample.com")
        .is_none());
}

//! Fixed classification cases for the rule document parser.
//!
//! These lines used to be compared step by step with the Dart parser; that parser is gone, so the
//! corpus is pinned here instead: every branch of a line (comments, cosmetic delimiters, URL and
//! regex forms, modifier families, hosts, dnsmasq and the awkward shapes around them) is covered by
//! one fixed document, and the family counts plus a set of exact patterns are asserted.

use diting_rule_core::parse_document;

const CORPUS: &[&str] = &[
    "! Title: test list",
    "# comment line",
    "[Adblock Plus 2.0]",
    r"||example.com^",
    r"||example.com^$important",
    r"||ads.net^$app=com.app1|com.app2,important",
    r"||tracker.com^$app=~com.android.chrome",
    r"||*-analytics.google.com^$app=com.google.android.gms",
    r"||safe.example.com^",
    r"@@||safe.example.com^",
    "@@",
    r"@@||a.com^$badfilter",
    r"||a.com^$badfilter",
    r"||example.com^$denyallow=a.com|b.com",
    r"||example.com^$denyallow=",
    r"||example.com^$~denyallow=a.com",
    r"||example.com^$denyallow=||a.com^|b.com.",
    r"||example.com^$dnstype=A|AAAA",
    r"||example.com^$~dnstype=A",
    r"||example.com^$dnstype=FOO",
    r"||example.com^$dnstype=",
    r"||example.com^$dnsrewrite=1.2.3.4",
    r"||example.com^$dnsrewrite=2001:db8::1",
    r"||example.com^$dnsrewrite=target.example.org",
    r"||example.com^$dnsrewrite=NXDOMAIN",
    r"||example.com^$dnsrewrite=nxdomain",
    r"||example.com^$dnsrewrite=REFUSED",
    r"||example.com^$dnsrewrite=SERVFAIL",
    r"||example.com^$dnsrewrite=0.0.0.0",
    r"||example.com^$dnsrewrite=::1",
    r"||example.com^$dnsrewrite=REFUSED;8.8.8.8",
    r"||example.com^$dnsrewrite=8.8.8.8;",
    r"||example.com^$dnsrewrite=a.example.com;b.example.com",
    r"||example.com^$dnsrewrite=",
    r"||example.com^$badfilter,dnsrewrite=1.2.3.4",
    r"||example.com^$image,third-party",
    r"||example.com^$removeparam=utm_source",
    r"||example.com/banner.js$script,badfilter",
    r"||example.com^$all",
    r"||example.com^$all,important",
    r"||example.com^$foo=bar",
    r"||example.com^$",
    r"||example.com^$important,",
    r"||example.com^$app=",
    r"||example.com^$app=~",
    r"||example.com^$important,important",
    r"/^ad[0-9]+\.example\.com$/",
    r"@@/^safe[0-9]+\.blocked\.com$/",
    r"/^ad[0-9]+\.example\.com$/$important",
    "/invalid(regex/",
    "/(/",
    "/)/",
    "/a**/",
    "/a{2}/",
    "/a{2,}/",
    "/a{2,4}/",
    "/a??/",
    "/(?:a|b)+/",
    "/[/",
    r"/a\/",
    "//",
    "/a/",
    "/a/b",
    "|http://example.com^",
    "|https://example.com/ad^",
    "||example.com/path^",
    "||*/path^",
    "*/ad/path",
    "/ads/banner.js",
    "example.com##.ad-banner",
    "example.com#@#.ad",
    "example.com#?#.ad",
    r"example.com#$#.ad { color: red }",
    r"example.com#$@#.ad-banner",
    "##.generic-ad",
    "a.com,b.com##.ad",
    "example.com##",
    "0.0.0.0 ads.example.com tracker.example.com # hosts comment",
    "127.0.0.1 local.example.com",
    "::1 v6.example.com",
    "1.2.3.4 host1.example.com host2.example.com",
    "10.0.0.2 real.com",
    "10.0.0.2 bad_host.com",
    "address=/blocked.com/",
    "address=/sink.com/0.0.0.0",
    "address=/null.com/#",
    "server=/a.example.com/1.2.3.4",
    "address=/a.example.com/b.example.com",
    "address=/a.example.com/1.2.3.4.5",
    "address=/",
    "server=/",
    "address=/a.com/b.com/ # dnsmasq comment",
    "address=/a.com/b.com/\t# tab comment",
    "address=/a.com, b.com/1.2.3.4",
    "address=/a.com/#",
    "address=/*.wild.com/",
    r"||example.com^ # trailing comment",
    "||example.com#comment",
    "||exa#mple.com^",
    "||example.com//#comment",
    r"||example.com^ $important",
    r"||example.com^$important # comment",
    "",
    "   ",
    "\u{FEFF}||bom.example.com^",
    "||UPPER.Case.COM^",
    "||中文.cn^",
    "||éxample.com^",
    "||a.com#é",
    "||a.com?é",
    "||a_b.com^",
    "||*.wild.com^",
    "||*^",
    "||^",
    "||",
    "@@||",
];

fn patterns(rules: &[diting_rule_core::ParsedRule]) -> Vec<&str> {
    rules.iter().map(|rule| rule.pattern.as_str()).collect()
}

#[test]
fn corpus_classification_is_pinned() {
    let parsed = parse_document(&CORPUS.join(
        "
",
    ));
    assert_eq!(parsed.total_lines, CORPUS.len() as u32);
    assert_eq!(parsed.block_rules.len(), 29);
    assert_eq!(parsed.allow_rules.len(), 2);
    assert_eq!(parsed.rewrite_rules.len(), 10);
    assert_eq!(parsed.url_block_rules.len(), 5);
    assert_eq!(parsed.url_allow_rules.len(), 0);
    assert_eq!(parsed.cosmetic_rules.len(), 8);
    assert_eq!(parsed.badfiltered_count, 2);
    assert_eq!(parsed.duplicate_count, 22);
    assert_eq!(parsed.invalid_count, 23);
    assert_eq!(parsed.unsupported_count, 9);
    // `||example.com/banner.js$script,badfilter` is a bad-filter declaration for a URL rule: the
    // content-type modifier is demoted and the line registers a bad-filter key instead of being
    // ignored, so it is no longer counted in `ignored_count` (it also emits no rule of its own).
    assert_eq!(parsed.ignored_count, 7);
}

#[test]
fn a_badfilter_url_line_registers_a_key_without_emitting_a_rule() {
    let line = diting_rule_core::parse_categorized_line("||example.com/banner.js$script,badfilter");
    assert!(line.block_rules.is_empty());
    assert!(line.url_block_rules.is_empty());
    assert_eq!(line.badfilter_keys.len(), 1);
    assert_eq!(line.ignored_count, 0);
}

#[test]
fn corpus_keeps_the_awkward_patterns() {
    let parsed = parse_document(&CORPUS.join(
        "
",
    ));
    let block = patterns(&parsed.block_rules);
    // Hosts lines expand one address into every name on the line.
    assert!(block.contains(&"ads.example.com"));
    assert!(block.contains(&"tracker.example.com"));
    // Case folding, regex bodies and the wildcard flag survive the document pass.
    assert!(block.contains(&"upper.case.com"));
    assert!(block.contains(&r"^ad[0-9]+\.example\.com$"));
    assert!(block.contains(&"*.wild.com"));
    assert!(block.contains(&"a{2,4}"));
    // A UTF-8 BOM keeps its byte in `rawLine` and does not stop the rule.
    assert!(block.contains(&"bom.example.com"));
    // Non-ASCII labels and `_` are rejected, exactly like the old parser.
    assert!(!block.contains(&"中文.cn"));
    assert!(!block.contains(&"a_b.com"));

    let rewrite = parsed
        .rewrite_rules
        .iter()
        .map(|rule| rule.pattern.as_str())
        .collect::<Vec<_>>();
    assert!(rewrite.contains(&"host1.example.com"));
    assert!(rewrite.contains(&"host2.example.com"));
    assert!(rewrite.contains(&"real.com"));
    // Sinkhole dnsrewrite targets become block rules, not rewrites.
    assert!(!rewrite.contains(&"sink.com"));
    assert!(block.contains(&"sink.com"));

    assert!(parsed
        .cosmetic_rules
        .iter()
        .any(|rule| rule.selector == ".ad-banner" && rule.is_exception));
}

#[test]
fn url_rule_keeps_app_scope() {
    let parsed = parse_document("||ads.example.com/banner.js$app=com.foo");
    assert_eq!(parsed.url_block_rules.len(), 1);
    assert_eq!(
        parsed.url_block_rules[0].app_scope.as_deref(),
        Some("com.foo")
    );
    assert!(parsed.block_rules.is_empty());
}

#[test]
fn sinkhole_dnsrewrite_targets_block() {
    for line in [
        "||blocked.com^$dnsrewrite=NXDOMAIN",
        "||sinkhole.com^$dnsrewrite=0.0.0.0",
        "||v6sink.com^$dnsrewrite=::1",
    ] {
        let parsed = parse_document(line);
        assert_eq!(parsed.block_rules.len(), 1, "{line}");
        assert!(parsed.rewrite_rules.is_empty(), "{line}");
    }
}

#[test]
fn web_only_modifiers_are_ignored() {
    for line in [
        "||example.com^$image,third-party",
        "||example.com^$removeparam=utm_source",
    ] {
        let parsed = parse_document(line);
        assert!(parsed.is_empty(), "{line}");
        assert_eq!(parsed.ignored_count, 1, "{line}");
    }
}

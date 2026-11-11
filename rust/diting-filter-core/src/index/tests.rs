//! Matcher behaviour, ported one for one from the Go tests the migration replaced
//! (`rule_test.go`, `rule_modifiers_test.go`, `rule_modifiers_rewrite_test.go`).

use super::*;
use crate::rule::{
    FLAG_ALLOW, FLAG_EXACT, FLAG_IMPORTANT, FLAG_REGEX, FLAG_REWRITE, FLAG_WILDCARD,
};
use diting_go_compat::regex::compile_rule_regex;

fn plain(pattern: &str) -> Rule {
    Rule::new(pattern)
}

fn allow(pattern: &str) -> Rule {
    Rule::new(pattern).with_flags(FLAG_ALLOW)
}

fn important_block(pattern: &str) -> Rule {
    Rule::new(pattern).with_flags(FLAG_IMPORTANT)
}

fn important_allow(pattern: &str) -> Rule {
    Rule::new(pattern).with_flags(FLAG_ALLOW | FLAG_IMPORTANT)
}

fn exact(pattern: &str) -> Rule {
    Rule::new(pattern).with_flags(FLAG_EXACT)
}

/// The source Go's `buildWildcardRegex` compiles for a wildcard pattern.
fn wildcard_source(pattern: &str) -> String {
    let mut source = String::from("(?i)^(?:.*\\.)?");
    for ch in pattern.chars() {
        if ch == '*' {
            source.push_str(".*");
        } else {
            source.push_str(&regex::escape(&ch.to_string()));
        }
    }
    source.push('$');
    source
}

/// A wildcard rule whose regex is built the way Go's `buildWildcardRegex` builds it.
fn wildcard(pattern: &str) -> Rule {
    Rule::new(pattern)
        .with_flags(FLAG_WILDCARD)
        .with_regex(compile_rule_regex(&wildcard_source(pattern)).expect("wildcard regex"))
}

fn wildcard_allow(pattern: &str) -> Rule {
    Rule::new(pattern)
        .with_flags(FLAG_WILDCARD | FLAG_ALLOW)
        .with_regex(compile_rule_regex(&wildcard_source(pattern)).expect("wildcard regex"))
}

fn wildcard_important_block(pattern: &str) -> Rule {
    Rule::new(pattern)
        .with_flags(FLAG_WILDCARD | FLAG_IMPORTANT)
        .with_regex(compile_rule_regex(&wildcard_source(pattern)).expect("wildcard regex"))
}

fn regex_rule(body: &str, is_allow: bool) -> Rule {
    let source = format!("(?i){body}");
    Rule::new(body)
        .with_flags(FLAG_REGEX | if is_allow { FLAG_ALLOW } else { 0 })
        .with_regex(compile_rule_regex(&source).expect("rule regex"))
}

fn rewrite(pattern: &str, flags: u8, rcode: u8, rrtype: u16, key: &str) -> Rule {
    let mut rule = Rule::new(pattern).with_flags(flags | FLAG_REWRITE);
    if flags & FLAG_WILDCARD != 0 {
        rule.regex = Some(compile_rule_regex(&wildcard_source(pattern)).expect("wildcard regex"));
    }
    rule.rewrite = Some(crate::rule::RewriteAction {
        bare: rcode == 0 && rrtype == 0 && key == "bare",
        rcode,
        rrtype,
        key: key.to_string(),
    });
    rule
}

fn index(rules: Vec<Rule>) -> FilterIndex {
    FilterIndex::build(rules)
}

const A: u16 = 1;
const AAAA: u16 = 28;
const MX: u16 = 15;
const TCP_PORT: u16 = 6;

#[test]
fn tiers_are_consulted_in_priority_order() {
    let index = index(vec![
        plain("blocked.com"),
        allow("allow.blocked.com"),
        important_block("important.allow.blocked.com"),
        important_allow("top.important.allow.blocked.com"),
    ]);

    let decision = index.match_domain("blocked.com", A);
    assert_eq!(decision.action, Action::Block);
    assert_eq!(decision.reason, Some(Reason::Blacklist));
    assert_eq!(decision.rule, Some(0));

    let decision = index.match_domain("allow.blocked.com", A);
    assert_eq!(decision.reason, Some(Reason::Whitelist));

    let decision = index.match_domain("important.allow.blocked.com", A);
    assert_eq!(decision.reason, Some(Reason::ImportantBlock));

    let decision = index.match_domain("top.important.allow.blocked.com", A);
    assert_eq!(decision.reason, Some(Reason::ImportantAllow));

    assert_eq!(index.match_domain("clean.com", A), Decision::pass());
    assert_eq!(index.match_domain("", A), Decision::pass());
}

#[test]
fn wildcard_and_regex_lists_answer_after_the_tries() {
    let index = index(vec![
        plain("blocked.com"),
        wildcard_allow("*.blocked.com"),
        regex_rule("^safe[0-9]+\\.blocked\\.com$", true),
        wildcard_important_block("*malware*.com"),
        allow("not-malware.com"),
    ]);

    assert_eq!(
        index.match_domain("sub.blocked.com", A).reason,
        Some(Reason::Whitelist)
    );
    assert_eq!(
        index.match_domain("safe1.blocked.com", A).reason,
        Some(Reason::Whitelist)
    );
    assert_eq!(
        index.match_domain("not-malware.com", A).reason,
        Some(Reason::ImportantBlock)
    );
    assert_eq!(
        index.match_domain("x-malware.com", A).reason,
        Some(Reason::ImportantBlock)
    );
}

#[test]
fn blocklist_pattern_rules_report_wildcard_or_regex() {
    let index = index(vec![
        wildcard("*.ads.test"),
        regex_rule("^ad[0-9]+\\.test$", false),
    ]);
    assert_eq!(
        index.match_domain("x.ads.test", A).reason,
        Some(Reason::WildcardBlock)
    );
    assert_eq!(
        index.match_domain("ad42.test", A).reason,
        Some(Reason::RegexBlock)
    );
}

#[test]
fn exact_rules_do_not_inherit_but_plain_ones_do() {
    let index = index(vec![exact("exact.test"), plain("ad.test")]);
    assert_eq!(index.match_domain("exact.test", A).action, Action::Block);
    assert_eq!(index.match_domain("sub.exact.test", A).action, Action::Pass);
    assert_eq!(index.match_domain("a.b.ad.test", A).action, Action::Block);
}

#[test]
fn dns_type_restrictions_apply_but_any_matches_everything() {
    let mut rule = plain("ipv6only.ad.com").with_dns_type(AAAA);
    rule.dns_type = AAAA;
    let index = index(vec![rule]);

    assert_eq!(
        index.match_domain("ipv6only.ad.com", A).action,
        Action::Pass
    );
    assert_eq!(
        index.match_domain("ipv6only.ad.com", AAAA).action,
        Action::Block
    );
    // `ANY` and the "unspecified" type bypass the restriction (Go's `matchDNSType`).
    assert_eq!(
        index
            .match_domain("ipv6only.ad.com", crate::rule::TYPE_ANY)
            .action,
        Action::Block
    );
    assert_eq!(
        index.match_domain("ipv6only.ad.com", 0).action,
        Action::Block
    );
}

#[test]
fn denyallow_excludes_the_target_and_falls_through_to_the_next_tier() {
    let mut denied = plain("ads.com");
    denied.deny_allow = vec!["good.ads.com".into()];
    let mut important = important_block("example.com");
    important.deny_allow = vec!["cdn.example.com".into()];
    let index = index(vec![denied, important, plain("cdn.example.com")]);

    assert!(index.has_deny_allow());

    for domain in ["good.ads.com", "sub.good.ads.com"] {
        assert_eq!(
            index.match_domain(domain, A).action,
            Action::Pass,
            "{domain}"
        );
    }
    for domain in ["ads.com", "bad.ads.com"] {
        assert_eq!(
            index.match_domain(domain, A).reason,
            Some(Reason::Blacklist),
            "{domain}"
        );
    }

    // The excluded `$important` rule falls through to the lower tier instead of passing.
    let decision = index.match_domain("cdn.example.com", A);
    assert_eq!(decision.reason, Some(Reason::Blacklist));
    assert_eq!(decision.rule, Some(2));
    assert_eq!(
        index.match_domain("other.example.com", A).reason,
        Some(Reason::ImportantBlock)
    );
}

#[test]
fn a_clean_index_reports_no_exclusions() {
    let index = index(vec![plain("ads.com")]);
    assert!(!index.has_deny_allow());
    assert_eq!(index.total_rules(), 1);
    assert_eq!(index.uncompiled_patterns(), 0);
}

#[test]
fn rewrite_answers_before_block_and_allow_rules() {
    let index = index(vec![
        plain("both.test"),
        important_block("imp.test"),
        rewrite("both.test", 0, 0, A, "0;1;1.2.3.4"),
        rewrite("imp.test", 0, 0, A, "0;1;1.2.3.4"),
    ]);

    let decision = index.match_domain("both.test", A);
    assert_eq!(decision.action, Action::Rewrite);
    assert_eq!(decision.rule, Some(2));
    assert_eq!(
        decision.rewrite,
        Some(RewriteAnswer {
            rcode: 0,
            rules: vec![2]
        })
    );

    let decision = index.match_domain("imp.test", A);
    assert_eq!(decision.action, Action::Rewrite);
}

#[test]
fn rewrite_cname_is_served_for_any_query_type() {
    let index = index(vec![rewrite(
        "cname.test",
        0,
        0,
        TYPE_CNAME,
        "0;5;new-cname.test",
    )]);
    for qtype in [A, AAAA, MX] {
        let decision = index.match_domain("cname.test", qtype);
        assert_eq!(decision.action, Action::Rewrite, "qtype {qtype}");
        assert_eq!(
            decision.rewrite,
            Some(RewriteAnswer {
                rcode: 0,
                rules: vec![0]
            })
        );
    }
}

#[test]
fn same_type_records_are_summed_and_other_types_are_nodata() {
    let index = index(vec![
        rewrite("multi.test", 0, 0, A, "0;1;127.0.0.1"),
        rewrite("multi.test", 0, 0, A, "0;1;127.0.0.2"),
    ]);

    assert_eq!(
        index.match_domain("multi.test", A).rewrite,
        Some(RewriteAnswer {
            rcode: 0,
            rules: vec![0, 1]
        })
    );
    assert_eq!(
        index.match_domain("multi.test", AAAA).rewrite,
        Some(RewriteAnswer {
            rcode: 0,
            rules: vec![]
        })
    );
}

#[test]
fn failure_codes_win_over_records() {
    let index = index(vec![
        rewrite("fail.test", 0, 0, A, "0;1;127.0.0.1"),
        rewrite("fail.test", 0, 2, 0, "2;0;"),
    ]);
    let decision = index.match_domain("fail.test", A);
    assert_eq!(
        decision.rewrite,
        Some(RewriteAnswer {
            rcode: 2,
            rules: vec![]
        })
    );
    assert_eq!(decision.rule, Some(1));
}

#[test]
fn a_valued_exception_cancels_only_the_matching_value() {
    let index = index(vec![
        rewrite("one.test", 0, 0, A, "0;1;127.0.0.1"),
        rewrite("one.test", 0, 0, A, "0;1;127.0.0.2"),
        rewrite("one.test", FLAG_ALLOW, 0, A, "0;1;127.0.0.1"),
    ]);
    assert_eq!(
        index.match_domain("one.test", A).rewrite,
        Some(RewriteAnswer {
            rcode: 0,
            rules: vec![1]
        })
    );
}

#[test]
fn a_bare_exception_cancels_every_rewrite_without_unblocking() {
    let cancelled = index(vec![
        rewrite("all.test", 0, 0, A, "0;1;127.0.0.1"),
        rewrite("all.test", 0, 0, A, "0;1;127.0.0.2"),
        rewrite("all.test", FLAG_ALLOW, 0, 0, "bare"),
    ]);
    assert_eq!(cancelled.match_domain("all.test", A), Decision::pass());

    let mixed = index(vec![
        rewrite("mix.test", 0, 0, A, "0;1;127.0.0.1"),
        plain("mix.test"),
        rewrite("mix.test", FLAG_ALLOW, 0, 0, "bare"),
    ]);
    let decision = mixed.match_domain("mix.test", A);
    assert_eq!(decision.action, Action::Block);
    assert_eq!(decision.reason, Some(Reason::Blacklist));
}

#[test]
fn rewrite_rules_inherit_to_subdomains_and_match_wildcards() {
    let index = index(vec![
        rewrite("parent.test", 0, 0, A, "0;1;127.0.0.1"),
        rewrite("*.wild.test", FLAG_WILDCARD, 0, A, "0;1;127.0.0.3"),
    ]);
    assert_eq!(
        index.match_domain("deep.sub.parent.test", A).rewrite,
        Some(RewriteAnswer {
            rcode: 0,
            rules: vec![0]
        })
    );
    let wild = index.match_domain("anything.wild.test", A);
    assert_eq!(wild.action, Action::Rewrite);
    assert_eq!(wild.rewrite.map(|answer| answer.rules), Some(vec![1]));
}

#[test]
fn an_exact_rewrite_rule_does_not_inherit() {
    let index = index(vec![{
        let mut rule = rewrite("exact.test", FLAG_EXACT, 0, A, "0;1;127.0.0.1");
        rule.flags |= FLAG_EXACT;
        rule
    }]);
    assert_eq!(index.match_domain("exact.test", A).action, Action::Rewrite);
    assert_eq!(index.match_domain("sub.exact.test", A).action, Action::Pass);
}

#[test]
fn pattern_rules_without_a_compiled_regex_never_match() {
    let index = index(vec![
        Rule::new("*.broken.test").with_flags(FLAG_WILDCARD),
        Rule::new("^broken[0-9]+\\.test$").with_flags(FLAG_REGEX),
    ]);
    assert_eq!(index.uncompiled_patterns(), 2);
    assert_eq!(index.match_domain("x.broken.test", A).action, Action::Pass);
    assert_eq!(index.match_domain("broken1.test", A).action, Action::Pass);
}

#[test]
fn total_rules_counts_rewrite_and_pattern_rules_too() {
    let index = index(vec![
        plain("a.test"),
        wildcard("*.b.test"),
        rewrite("c.test", 0, 0, A, "0;1;127.0.0.1"),
    ]);
    assert_eq!(index.total_rules(), 3);
    let _ = TCP_PORT;
}

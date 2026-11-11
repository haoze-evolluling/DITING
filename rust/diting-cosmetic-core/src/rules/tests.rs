//! Unit tests for the rule set: the suffix walk, the hide/exception merge and the sentinels.

use std::collections::HashMap;

use super::*;

fn rules(
    hide: &[&str],
    global_exception: &[&str],
    domains: &[(&str, &[&str], &[&str])],
) -> RuleSet {
    let mut map = HashMap::new();
    for (domain, hidden, excepted) in domains {
        map.insert(
            (*domain).to_string(),
            DomainRules {
                hide: hidden.iter().map(|item| (*item).to_string()).collect(),
                exception: excepted.iter().map(|item| (*item).to_string()).collect(),
            },
        );
    }
    RuleSet::Loaded(Rules {
        global_hide: hide.iter().map(|item| (*item).to_string()).collect(),
        global_exception: global_exception
            .iter()
            .map(|item| (*item).to_string())
            .collect(),
        domains: map,
    })
}

#[test]
fn the_suffix_walk_stops_at_the_last_label() {
    assert_eq!(
        host_suffixes("ads.example.com"),
        vec!["ads.example.com", "example.com", "com"]
    );
    assert_eq!(host_suffixes("com"), vec!["com"]);
    assert_eq!(host_suffixes(""), Vec::<String>::new());
    // Normalization happens first, so a port and a trailing dot never reach the walk.
    assert_eq!(
        host_suffixes("Ads.Example.com.:443"),
        vec!["ads.example.com", "example.com", "com"]
    );
    // A trailing dot inside the normalized name cannot happen, but a doubled dot can.
    assert_eq!(host_suffixes("a..b"), vec!["a..b", ".b", "b"]);
}

#[test]
fn a_host_rule_reaches_its_subdomains() {
    let set = rules(
        &[".global"],
        &[],
        &[("example.com", &[".banner"], &[]), ("com", &[".tld"], &[])],
    );
    let css = set.render("ads.example.com");
    assert_eq!(
        css,
        ".banner { display: none !important; }\n\
         .global { display: none !important; }\n\
         .tld { display: none !important; }\n"
    );
}

#[test]
fn an_unrelated_host_only_gets_the_global_rules() {
    let set = rules(&[".global"], &[], &[("example.com", &[".banner"], &[])]);
    assert_eq!(
        set.render("unrelated.org"),
        ".global { display: none !important; }\n"
    );
}

#[test]
fn an_exception_wins_over_every_hide() {
    // A host-scoped hide of a globally excepted selector must lose: exceptions are applied after
    // the walk.
    let set = rules(
        &[".generic-ad", ".promo"],
        &[".generic-ad"],
        &[("example.com", &[".generic-ad"], &[])],
    );
    assert_eq!(
        set.render("example.com"),
        ".promo { display: none !important; }\n\
         .generic-ad { display: revert !important; }\n"
    );
}

#[test]
fn a_scoped_exception_reverts_an_inherited_hide() {
    let set = rules(&[".site"], &[], &[("example.com", &[".site"], &[".site"])]);
    assert_eq!(
        set.render("www.example.com"),
        ".site { display: revert !important; }\n"
    );
}

#[test]
fn the_two_sentinels_are_the_old_early_returns() {
    assert_eq!(RuleSet::Empty.render("x.com"), NO_RULES);
    assert_eq!(RuleSet::Invalid.render("x.com"), INVALID_RULES);
    assert!(RuleSet::Empty.is_empty());
    assert!(
        !RuleSet::Invalid.is_empty(),
        "an undecodable payload must still inject the <link>"
    );
    assert!(!rules(&[], &[], &[]).is_empty());
}

#[test]
fn an_empty_rule_set_renders_nothing() {
    assert_eq!(rules(&[], &[], &[]).render("example.com"), "");
}

#[test]
fn selectors_are_sorted_by_bytes() {
    let set = rules(&[".b", "A", ".a", "é"], &[], &[]);
    // `sort.Strings` is byte order, so `.a` < `.b` < `A` < `é`.
    assert_eq!(
        set.render("example.com"),
        ".a { display: none !important; }\n\
         .b { display: none !important; }\n\
         A { display: none !important; }\n\
         é { display: none !important; }\n"
    );
}

#[test]
fn the_empty_selector_is_kept() {
    // The old Go code put selectors into a map without filtering, so `""` rendered a bare line.
    let set = rules(&[""], &[], &[]);
    assert_eq!(
        set.render("example.com"),
        " { display: none !important; }\n"
    );
}

#[test]
fn duplicate_selectors_render_once() {
    let set = rules(&[".dup", ""], &[], &[("example.com", &[".dup"], &[])]);
    let css = set.render("example.com");
    assert_eq!(css.matches(".dup").count(), 1);
}

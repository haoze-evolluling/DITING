//! The snapshot builder: every classification branch, the export order and the JSON shape.
//!
//! The expectations below are the Kotlin `BlockRuleLoader` / `AllowRuleLoader` / `buildJson`
//! semantics read line by line; `serde_json::Value` keeps map order irrelevant while array order is
//! asserted exactly (the Go policy kernel loads maps, but the exported lists are ordered).

use serde_json::Value;

use super::*;

fn row(pattern: &str) -> Row {
    Row {
        pattern: pattern.to_string(),
        source: "custom".to_string(),
        important: false,
        app_scope: None,
        app_inverted: false,
        is_wildcard: false,
        denyallow: None,
        is_regex: false,
        dns_type: None,
    }
}

fn source(mut row: Row, source: &str) -> Row {
    row.source = source.to_string();
    row
}

fn important(mut row: Row) -> Row {
    row.important = true;
    row
}

fn wildcard(mut row: Row) -> Row {
    row.is_wildcard = true;
    row
}

fn scope(mut row: Row, scope: &str) -> Row {
    row.app_scope = Some(scope.to_string());
    row
}

fn inverted(mut row: Row) -> Row {
    row.app_inverted = true;
    row
}

fn regex(mut row: Row) -> Row {
    row.is_regex = true;
    row
}

fn denyallow(mut row: Row, denyallow: &str) -> Row {
    row.denyallow = Some(denyallow.to_string());
    row
}

fn dns_type(mut row: Row, dns_type: &str) -> Row {
    row.dns_type = Some(dns_type.to_string());
    row
}

fn strings(value: &Value) -> Vec<&str> {
    value
        .as_array()
        .unwrap_or_else(|| panic!("expected an array, got {value}"))
        .iter()
        .map(|item| item.as_str().expect("array elements are strings"))
        .collect()
}

fn document(input: &SnapshotInput) -> Value {
    serde_json::from_str(&build(input)).expect("the builder emits JSON")
}

fn classified() -> SnapshotInput {
    SnapshotInput {
        filter_enabled: true,
        trie_paths: [
            Some("/data/rule-index/domain/block.trie".to_string()),
            Some("/data/rule-index/domain/block.important.trie".to_string()),
            Some("/data/rule-index/domain/allow.trie".to_string()),
            None,
        ],
        app_allowlist: vec![("com.user".to_string(), vec!["user.com".to_string()])],
        block: LoadInput {
            index_usable: true,
            important_usable: true,
            custom: vec![
                source(row("a.com"), "custom"),
                important(row("b.com")),
                wildcard(row("*.w.com")),
                important(wildcard(row("*.iw.com"))),
                scope(row("scoped.com"), "com.a|com.b"),
                important(scope(row("imp-scoped.com"), "com.a")),
                inverted(scope(row("inv.com"), "com.c| com.c ")),
                regex(row("^regex$")),
                denyallow(row("deny.com"), "keep.com"),
                dns_type(row("aaaa.com"), "~AAAA"),
            ],
            subscription: vec![
                source(row("plain-sub.com"), "sub_one"),
                important(row("important-sub.com")),
                wildcard(row("*.sub-wc.com")),
                scope(row("sub-scoped.com"), "com.b"),
                inverted(scope(row("inv-sub.com"), "com.d")),
                denyallow(row("sub-deny.com"), "keep.com"),
            ],
        },
        allow: LoadInput {
            index_usable: true,
            important_usable: true,
            custom: vec![
                row("allow.com"),
                wildcard(row("*.allow-wc.com")),
                important(row("allow-imp.com")),
                scope(row("allow-scoped.com"), "com.a"),
                regex(row("^allow-regex$")),
            ],
            subscription: vec![
                row("allow-sub-skipped.com"),
                important(row("allow-sub-imp-skipped.com")),
                wildcard(row("*.allow-sub-wc.com")),
            ],
        },
    }
}

#[test]
fn block_lists_keep_the_kotlin_export_order() {
    let json = document(&classified());
    assert_eq!(json["filterEnabled"], Value::Bool(true));
    assert_eq!(json["blockTriePath"], "/data/rule-index/domain/block.trie");
    assert_eq!(
        json["importantBlockTriePath"],
        "/data/rule-index/domain/block.important.trie"
    );
    assert_eq!(json["allowTriePath"], "/data/rule-index/domain/allow.trie");
    // A null path is omitted, not serialized as null.
    assert!(json.get("importantAllowTriePath").is_none());

    // custom exact, custom wildcards, subscription exact (skipped: the trie holds it), wildcards.
    assert_eq!(
        strings(&json["globalBlock"]),
        vec!["a.com", "*.w.com", "*.sub-wc.com"]
    );
    assert_eq!(strings(&json["globalImportant"]), vec!["b.com", "*.iw.com"]);
    assert!(strings(&json["disabledRules"]).is_empty());
}

#[test]
fn plain_subscription_rules_are_inlined_when_the_trie_is_missing() {
    let mut input = classified();
    input.block.index_usable = false;
    input.block.important_usable = false;
    let json = document(&input);
    assert_eq!(
        strings(&json["globalBlock"]),
        vec!["a.com", "*.w.com", "plain-sub.com", "*.sub-wc.com"]
    );
    assert_eq!(
        strings(&json["globalImportant"]),
        vec!["b.com", "*.iw.com", "important-sub.com"]
    );

    // The allow half is gated by its own flags: usable here, so its plain rows stay out. App-scoped
    // rows never reach a global list.
    assert_eq!(
        strings(&json["globalAllow"]),
        vec![
            "allow.com",
            "*.allow-wc.com",
            "allow-imp.com",
            "*.allow-sub-wc.com",
        ]
    );
}

#[test]
fn the_allow_half_inlines_its_plain_rows_when_its_trie_is_missing() {
    let mut input = classified();
    input.allow.index_usable = false;
    input.allow.important_usable = false;
    let json = document(&input);
    assert_eq!(
        strings(&json["globalAllow"]),
        vec![
            "allow.com",
            "*.allow-wc.com",
            "allow-imp.com",
            "allow-sub-skipped.com",
            "*.allow-sub-wc.com",
            "allow-sub-imp-skipped.com",
        ]
    );
}

#[test]
fn app_rules_merge_both_halves_and_the_user_allowlist() {
    let json = document(&classified());
    let app = &json["appRules"];
    // Allow buckets first, then block buckets, then the user allowlist (serde_json sorts the
    // object keys, so the order only shows up in which packages exist).
    let mut packages: Vec<&String> = json["appRules"].as_object().unwrap().keys().collect();
    packages.sort();
    assert_eq!(packages, vec!["com.a", "com.b", "com.user"]);
    assert_eq!(strings(&app["com.a"]["allow"]), vec!["allow-scoped.com"]);
    assert_eq!(strings(&app["com.a"]["block"]), vec!["scoped.com"]);
    assert_eq!(strings(&app["com.a"]["important"]), vec!["imp-scoped.com"]);
    assert_eq!(strings(&app["com.b"]["allow"]), Vec::<&str>::new());
    // `scoped.com` names com.a and com.b, so it lands in both packages.
    assert_eq!(
        strings(&app["com.b"]["block"]),
        vec!["scoped.com", "sub-scoped.com"]
    );
    assert_eq!(strings(&app["com.b"]["important"]), Vec::<&str>::new());
    assert_eq!(strings(&app["com.user"]["allow"]), vec!["user.com"]);
    assert_eq!(strings(&app["com.user"]["block"]), Vec::<&str>::new());
    assert_eq!(strings(&app["com.user"]["important"]), Vec::<&str>::new());
}

#[test]
fn inverted_rules_keep_their_shape_and_deduplicated_packages() {
    let json = document(&classified());
    let block = json["invertedBlock"].as_array().unwrap();
    assert_eq!(block.len(), 2);
    assert_eq!(block[0]["pattern"], "inv.com");
    assert_eq!(block[0]["source"], "custom");
    assert_eq!(block[0]["important"], Value::Bool(false));
    assert_eq!(strings(&block[0]["excludedApps"]), vec!["com.c"]);
    assert_eq!(block[1]["pattern"], "inv-sub.com");
    assert_eq!(strings(&block[1]["excludedApps"]), vec!["com.d"]);
    // Allow has no inverted rows in this fixture.
    assert!(json["invertedAllow"].as_array().unwrap().is_empty());
}

#[test]
fn special_rules_carry_source_only_on_the_block_side() {
    let json = document(&classified());
    let block = json["specialBlock"].as_array().unwrap();
    let patterns: Vec<&str> = block
        .iter()
        .map(|rule| rule["pattern"].as_str().expect("pattern"))
        .collect();
    assert_eq!(
        patterns,
        vec!["^regex$", "deny.com", "aaaa.com", "sub-deny.com"]
    );
    assert_eq!(block[0]["source"], "custom");
    assert_eq!(block[0]["isWildcard"], Value::Bool(false));
    assert!(block[0].get("appScope").is_none());
    assert!(block[0].get("denyallow").is_none());
    assert_eq!(block[1]["denyallow"], "keep.com");
    assert_eq!(block[2]["dnsType"], "~AAAA");

    let allow = json["specialAllow"].as_array().unwrap();
    assert_eq!(allow.len(), 1);
    assert_eq!(allow[0]["pattern"], "^allow-regex$");
    assert!(allow[0].get("source").is_none());
    assert_eq!(allow[0]["isRegex"], Value::Bool(true));
}

#[test]
fn an_empty_snapshot_matches_the_kotlin_empty_document() {
    let json = document(&SnapshotInput {
        filter_enabled: false,
        ..SnapshotInput::default()
    });
    let object = json.as_object().expect("the document is an object");
    // `serde_json::Value` sorts object keys; the Go side is order-insensitive either way.
    let mut keys: Vec<&str> = object.keys().map(String::as_str).collect();
    keys.sort();
    let mut expected = vec![
        "filterEnabled",
        "globalAllow",
        "globalBlock",
        "globalImportant",
        "appRules",
        "invertedBlock",
        "invertedAllow",
        "disabledRules",
        "specialBlock",
        "specialAllow",
    ];
    expected.sort();
    assert_eq!(keys, expected);
    assert_eq!(json["filterEnabled"], Value::Bool(false));
    for key in [
        "globalAllow",
        "globalBlock",
        "globalImportant",
        "invertedBlock",
        "invertedAllow",
        "disabledRules",
        "specialBlock",
        "specialAllow",
    ] {
        assert!(
            json[key].as_array().unwrap().is_empty(),
            "{key} must be an empty array"
        );
    }
    assert!(json["appRules"].as_object().unwrap().is_empty());
}

#[test]
fn an_empty_app_scope_is_preserved_on_a_special_rule() {
    let mut input = SnapshotInput::default();
    input.block.custom.push(scope(regex(row("^x$")), ""));
    let json = document(&input);
    assert_eq!(json["specialBlock"][0]["appScope"], "");
}

#[test]
fn the_policy_kernel_decodes_the_document() {
    // The Go engine hands this exact document to `diting-policy-core`; parse it with that kernel's
    // model so a renamed or reshaped field fails here instead of silently dropping rules.
    let document = build(&classified());
    let parsed = diting_policy_core::json::RuleSnapshot::parse(document.as_bytes())
        .expect("the policy kernel accepts the snapshot document");
    assert_eq!(parsed.filter_enabled, Some(true));
    assert_eq!(
        parsed.block_trie_path.as_deref(),
        Some("/data/rule-index/domain/block.trie")
    );
    assert_eq!(parsed.strings(&parsed.global_block).len(), 3);
    assert_eq!(parsed.strings(&parsed.global_important).len(), 2);
    assert_eq!(parsed.strings(&parsed.global_allow).len(), 4);
    let app = &parsed.app_rules.as_ref().expect("app rules")["com.a"];
    assert_eq!(
        app.allow.as_ref().unwrap(),
        &vec!["allow-scoped.com".to_string()]
    );
    assert_eq!(app.block.as_ref().unwrap(), &vec!["scoped.com".to_string()]);
    assert_eq!(
        app.important.as_ref().unwrap(),
        &vec!["imp-scoped.com".to_string()]
    );
    let inverted = parsed.inverted_block.as_ref().expect("inverted rules");
    assert_eq!(inverted.len(), 2);
    assert_eq!(inverted[0].pattern.as_deref(), Some("inv.com"));
    assert_eq!(
        inverted[0].excluded_apps.as_ref().unwrap(),
        &vec!["com.c".to_string()]
    );
    let special = parsed.special_block.as_ref().expect("special rules");
    assert_eq!(special.len(), 4);
    assert_eq!(special[1].denyallow.as_deref(), Some("keep.com"));
    let special_allow = parsed.special_allow.as_ref().expect("special allow");
    assert!(special_allow[0].source.is_none());
    assert_eq!(special_allow[0].is_regex, Some(true));
}

#[test]
fn an_empty_app_scope_counts_as_global_but_whitespace_does_not() {
    let mut input = SnapshotInput::default();
    input.block.custom = vec![
        scope(row("empty.com"), ""),
        scope(row("drops.com"), " | "),
        inverted(scope(row("inv-empty.com"), " | ")),
    ];
    let json = document(&input);
    // `isNullOrEmpty()` lets the empty string through to the global list.
    assert_eq!(strings(&json["globalBlock"]), vec!["empty.com"]);
    // " | " is a non-empty scope with no packages: the row lands in no bucket.
    let inverted_rules = json["invertedBlock"].as_array().unwrap();
    assert_eq!(inverted_rules.len(), 1);
    assert_eq!(inverted_rules[0]["pattern"], "inv-empty.com");
    assert!(strings(&inverted_rules[0]["excludedApps"]).is_empty());
}

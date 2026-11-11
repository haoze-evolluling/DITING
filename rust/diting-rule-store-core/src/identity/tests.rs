use serde_json::json;

use super::{identity, predicate, rewrite_target_type, Flavor, TargetType};

#[test]
fn a_target_is_an_address_or_a_hostname() {
    // The set `InternetAddress.tryParse` accepts, verbatim: no leading zeros, no zone ids, no
    // brackets, exactly four octets.
    for (target, expected) in [
        (None, TargetType::Cname),
        (Some(""), TargetType::Cname),
        (Some("1.1.1.1"), TargetType::Ipv4),
        (Some("010.0.0.1"), TargetType::Cname),
        (Some("256.1.1.1"), TargetType::Cname),
        (Some("1.2.3"), TargetType::Cname),
        (Some("1.2.3.4.5"), TargetType::Cname),
        (Some("::1"), TargetType::Ipv6),
        (Some("::ffff:1.1.1.1"), TargetType::Ipv6),
        (Some("fe80::1%eth0"), TargetType::Cname),
        (Some("[::1]"), TargetType::Cname),
        (Some("d.example"), TargetType::Cname),
    ] {
        assert_eq!(rewrite_target_type(target), expected, "target {target:?}");
    }
}

#[test]
fn the_global_identity_covers_every_unique_key_column() {
    let rule = json!({"pattern": "a.test", "important": false, "appScope": null,
                      "appInverted": false, "dnsType": null, "isRegex": false});
    let built = identity("block", Flavor::Global, &rule, None, 1000);
    assert_eq!(built.table, "block_rule");
    assert_eq!(built.source_table, "block_rule_source");
    assert_eq!(
        built.where_sql,
        "pattern = ? AND important = ? AND appScope IS NULL AND appInverted = ? \
         AND dnsType IS NULL AND isRegex = ?"
    );
    assert_eq!(
        built.args,
        vec![json!("a.test"), json!(0), json!(0), json!(0)]
    );
    // A new rule writes every flag the engine reads instead of relying on a column default.
    assert_eq!(built.row["enabled"], json!(1));
    assert_eq!(built.row["appScope"], json!(null));
    assert_eq!(built.row["isWildcard"], json!(0));
    assert_eq!(built.row["addedAt"], json!(1000));
}

#[test]
fn a_scoped_rule_uses_its_own_identity() {
    let rule = json!({"pattern": "a.test", "important": true});
    let built = identity("allow", Flavor::Scoped, &rule, Some("com.a"), 1000);
    assert_eq!(built.table, "allow_rule");
    // Deliberately narrower than the global identity: no `dnsType` / `isRegex`.
    assert_eq!(
        built.where_sql,
        "pattern = ? AND important = ? AND appScope = ? AND appInverted = 0"
    );
    assert_eq!(built.args, vec![json!("a.test"), json!(1), json!("com.a")]);
    assert_eq!(built.row["appScope"], json!("com.a"));
    assert_eq!(built.row["rawLine"], json!("a.test"));
    assert_eq!(built.row["important"], json!(1));
}

#[test]
fn the_full_block_marker_matches_any_slice_of_the_scope_list() {
    let rule = json!({"pattern": "*"});
    let built = identity("block", Flavor::FullBlock, &rule, Some("com.a"), 1000);
    assert_eq!(
        built.where_sql,
        "pattern = ? AND appInverted = 0 AND (appScope = ? OR appScope LIKE ? \
         OR appScope LIKE ? OR appScope LIKE ?)"
    );
    assert_eq!(
        built.args,
        vec![
            json!("*"),
            json!("com.a"),
            json!("com.a|%"),
            json!("%|com.a|%"),
            json!("%|com.a"),
        ]
    );
    assert_eq!(built.row["rawLine"], json!("*$app=com.a"));
    assert_eq!(built.row["isWildcard"], json!(1));
    assert_eq!(built.row["appScope"], json!("com.a"));
}

#[test]
fn a_rewrite_identity_is_the_target_triple() {
    let rule = json!({"pattern": "a.test", "target": "1.1.1.1"});
    let built = identity("rewrite", Flavor::Global, &rule, None, 1000);
    assert_eq!(built.table, "rewrite_rule");
    assert_eq!(
        built.where_sql,
        "pattern = ? AND targetType = ? AND targetValue = ?"
    );
    assert_eq!(built.target_type, TargetType::Ipv4);
    assert_eq!(
        built.args,
        vec![json!("a.test"), json!("IPv4"), json!("1.1.1.1")]
    );
    assert_eq!(built.row["targetType"], json!("IPv4"));
    // A rewrite row keeps its line: the app shows it, the engine ignores it.
    assert_eq!(built.row["rawLine"], json!("a.test"));
    assert_eq!(built.row["enabled"], json!(1));

    let cleared = identity(
        "rewrite",
        Flavor::Global,
        &json!({"pattern": "a.test", "target": null}),
        None,
        1000,
    );
    assert_eq!(cleared.target_type, TargetType::Cname);
    assert_eq!(cleared.row["targetValue"], json!(null));
}

#[test]
fn the_app_predicates_share_one_scope_clause() {
    let (scope, args) = predicate("scope", "com.a");
    assert_eq!(
        scope,
        "(appScope = ? OR appScope LIKE ? OR appScope LIKE ? OR appScope LIKE ?)"
    );
    assert_eq!(
        args,
        vec![
            json!("com.a"),
            json!("com.a|%"),
            json!("%|com.a|%"),
            json!("%|com.a")
        ]
    );

    // Rules loaded for one app never include the `*` marker.
    let (where_sql, args) = predicate("loadForApp", "com.a");
    assert_eq!(
        where_sql,
        "(appScope = ? OR appScope LIKE ? OR appScope LIKE ? OR appScope LIKE ?) AND appInverted = 0 AND pattern <> ?"
    );
    assert_eq!(args[0], json!("com.a"), "the scope args come first");
    assert_eq!(args[4], json!("*"), "the pattern argument is last");

    let (where_sql, _) = predicate("fullBlock", "com.a");
    assert!(where_sql.starts_with("pattern = ? AND appInverted = 0 AND (appScope = ?"));
    let (where_sql, _) = predicate("fullBlockEnabled", "com.a");
    assert!(where_sql.contains("enabled = 1"));
}

use serde_json::json;

use super::{
    import_plan, page_query, remove_source_plan, set_source_enabled_plan, summary, tables_plan,
    ORPHAN_PAGE_SIZE,
};

fn parsed() -> serde_json::Value {
    json!({
        "blockRules": [
            {"pattern": "a.test", "rawLine": "@@a.test", "important": true,
             "appScope": "com.a", "appInverted": false, "isWildcard": false,
             "denyallow": null, "isRegex": false, "dnsType": null},
        ],
        "allowRules": [{"pattern": "b.test", "rawLine": "b.test"}],
        "rewriteRules": [{"pattern": "c.test", "targetType": "IPv4",
                          "targetValue": "1.1.1.1", "rawLine": "c.test 1.1.1.1"}],
        "urlBlockRules": [
            {"pattern": "https://a.test/x", "rawLine": "|https://a.test/x", "isAllow": false},
            {"pattern": "https://a.test/y", "rawLine": "|https://a.test/y",
             "isAllow": false, "appScope": "com.a"},
        ],
        "urlAllowRules": [{"pattern": "https://b.test", "rawLine": "@@||b.test",
                           "isAllow": true}],
        "cosmeticRules": [{"domain": "a.test", "selector": ".ad"}],
        "duplicateCount": 2,
        "invalidCount": 1,
        "unsupportedCount": 3,
        "badfilteredCount": 4,
    })
}

#[test]
fn an_import_queues_one_batch_per_family_and_chunk() {
    let plan = import_plan(&parsed(), "sub_4", "domain", true, 1000, 7000);
    let families: Vec<&str> = plan
        .batches
        .iter()
        .map(|batch| batch["family"].as_str().unwrap())
        .collect();
    assert_eq!(
        families,
        vec!["block", "allow", "rewrite", "urlBlock", "urlAllow"]
    );

    // Two statements per rule: the conditional insert and the source link that is counted.
    let block = plan.batches[0]["steps"].as_array().unwrap();
    assert_eq!(block.len(), 2);
    assert_eq!(block[0]["changes"], json!(false));
    assert_eq!(block[1]["changes"], json!(true));
    assert!(block[0]["sql"]
        .as_str()
        .unwrap()
        .contains("WHERE NOT EXISTS (SELECT 1 FROM block_rule WHERE pattern = ?"));
    // The key predicate is appended after the column values.
    let args = block[0]["args"].as_array().unwrap();
    assert_eq!(args[1], json!("@@a.test"));
    assert_eq!(args[4], json!("com.a"));
    assert_eq!(args[10], json!("a.test"), "key args come last");

    // A `$app=` URL rule is skipped rather than stored as a global block.
    let url_block = plan.batches[3]["steps"].as_array().unwrap();
    assert_eq!(url_block.len(), 2);
    assert_eq!(url_block[1]["args"][0], json!("sub_4"));
    assert_eq!(
        url_block[1]["args"][1],
        json!(1),
        "enabled follows the subscription"
    );

    assert_eq!(plan.type_skipped, 0);
    assert_eq!(plan.cosmetic, 1);
    let counters = summary(&plan, &parsed());
    assert_eq!(counters["duplicate"], json!(2));
    assert_eq!(counters["badfiltered"], json!(4));
}

#[test]
fn chunks_split_a_family_without_changing_its_order() {
    let many = json!({
        "blockRules": [
            {"pattern": "a.test", "rawLine": "a.test"},
            {"pattern": "b.test", "rawLine": "b.test"},
            {"pattern": "c.test", "rawLine": "c.test"},
        ],
    });
    let plan = import_plan(&many, "useradd", "domain", false, 2, 1);
    assert_eq!(plan.batches.len(), 2);
    assert_eq!(plan.batches[0]["steps"].as_array().unwrap().len(), 4);
    assert_eq!(plan.batches[1]["steps"].as_array().unwrap().len(), 2);
    // A disabled subscription still writes the rules, only the source rows start off.
    assert_eq!(
        plan.batches[0]["steps"][1]["args"][1],
        json!(0),
        "source enabled flag"
    );
}

#[test]
fn a_hosts_dataset_drops_the_families_its_table_cannot_hold() {
    let plan = import_plan(&parsed(), "sub_4", "hosts", true, 1000, 1);
    let families: Vec<&str> = plan
        .batches
        .iter()
        .map(|batch| batch["family"].as_str().unwrap())
        .collect();
    assert_eq!(families, vec!["block", "rewrite"]);
    // Allow and URL rules are parsed but cannot be stored: they are reported, not dropped silently.
    // One allow rule plus two URL blocks and one URL allow.
    assert_eq!(plan.type_skipped, 4);
    assert_eq!(plan.cosmetic, 0);
}

#[test]
fn a_rule_without_spaces_still_produces_an_empty_plan() {
    let plan = import_plan(&json!({}), "sub_4", "domain", true, 1000, 1);
    assert!(plan.batches.is_empty());
    assert_eq!(plan.cosmetic, 0);
    assert_eq!(plan.type_skipped, 0);
}

#[test]
fn table_names_come_from_one_place() {
    let tables = tables_plan();
    assert_eq!(tables["block"]["table"], json!("block_rule"));
    assert_eq!(tables["allow"]["sourceTable"], json!("allow_rule_source"));
    assert_eq!(tables["rewrite"]["table"], json!("rewrite_rule"));
    assert_eq!(tables["url"]["table"], json!("go_url_rule"));
    assert_eq!(tables["url"]["sourceTable"], json!("go_url_rule_source"));
    // A user sweep deletes these three; `preset` and `sub_*` survive it.
    assert_eq!(
        tables["userSources"],
        json!(["useradd", "local_import", "local_hosts"])
    );
}

#[test]
fn a_source_sweep_deletes_source_rows_then_sweeps_orphans_in_pages() {
    let plan = remove_source_plan("sub_4");
    let steps = plan["steps"].as_array().unwrap();
    assert_eq!(steps.len(), 4, "one delete per source table");
    assert_eq!(
        steps[0]["sql"],
        json!("DELETE FROM block_rule_source WHERE source = ?")
    );
    assert_eq!(steps[0]["args"], json!(["sub_4"]));
    let orphans = plan["orphans"].as_array().unwrap();
    assert_eq!(orphans.len(), 4);
    assert_eq!(orphans[0]["table"], json!("block_rule"));
    assert_eq!(orphans[0]["selectArgs"], json!([ORPHAN_PAGE_SIZE]));
    assert!(orphans[0]["selectSql"]
        .as_str()
        .unwrap()
        .contains("NOT EXISTS (SELECT 1 FROM block_rule_source s WHERE s.ruleId = block_rule.id)"));
    assert_eq!(
        orphans[3]["deletePrefix"],
        json!("DELETE FROM go_url_rule WHERE id IN (")
    );
}

#[test]
fn toggling_a_source_updates_every_source_table() {
    let plan = set_source_enabled_plan("sub_4", false);
    let steps = plan["steps"].as_array().unwrap();
    assert_eq!(steps.len(), 4);
    assert_eq!(
        steps[2]["sql"],
        json!("UPDATE rewrite_rule_source SET enabled = ? WHERE source = ?")
    );
    assert_eq!(steps[2]["args"], json!([0, "sub_4"]));
}

#[test]
fn a_page_query_walks_ids_downwards_with_its_sources_joined_in() {
    let query = page_query("block", Some(500), Some(800));
    let sql = query["sql"].as_str().unwrap();
    assert!(sql.contains("WHERE id < ?"));
    assert!(sql.contains("LIMIT ?"));
    assert!(sql.contains("LEFT JOIN block_rule_source s ON s.ruleId = r.id"));
    assert_eq!(query["args"], json!([500, 800]));

    let first = page_query("rewrite", None, None);
    let sql = first["sql"].as_str().unwrap();
    assert!(!sql.contains("WHERE"));
    assert!(!sql.contains("LIMIT"));
    assert!(sql.contains("LEFT JOIN rewrite_rule_source"));
    assert_eq!(first["args"], json!([]));
}

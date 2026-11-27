use serde_json::json;

use super::{
    batches_json, commit_source_plan, import_plan, page_query, plan_json, remove_source_plan,
    set_source_enabled_plan, summary, tables_plan, ORPHAN_PAGE_SIZE,
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
    let parsed = parsed();
    let plan = import_plan(&parsed, "sub_4", "domain", true, 1000, 7000);
    let batches = batches_json(&plan.batches);
    let families: Vec<&str> = batches
        .iter()
        .map(|batch| batch["family"].as_str().unwrap())
        .collect();
    assert_eq!(
        families,
        vec!["block", "allow", "rewrite", "urlBlock", "urlAllow"]
    );

    let block = batches[0]["steps"].as_array().unwrap();
    assert_eq!(
        block.len(),
        6,
        "temp setup + bulk insert + dedupe + link + cleanup"
    );
    assert!(block[0]["sql"]
        .as_str()
        .unwrap()
        .starts_with("CREATE TEMP TABLE IF NOT EXISTS diting_import_domain"));
    assert!(block[2]["sql"]
        .as_str()
        .unwrap()
        .starts_with("INSERT INTO diting_import_domain"));
    assert!(block[3]["sql"]
        .as_str()
        .unwrap()
        .contains("FROM diting_import_domain t"));
    assert!(block[3]["sql"]
        .as_str()
        .unwrap()
        .contains("r.denyallow IS t.denyallow"));
    assert_eq!(block[3]["changes"], json!(false));
    assert_eq!(block[4]["changes"], json!(true));
    assert_eq!(block[4]["args"][0], json!("sub_4"));
    assert_eq!(block[4]["args"][1], json!(1));
    assert_eq!(block[5]["sql"], json!("DELETE FROM diting_import_domain"));

    let url_block = batches[3]["steps"].as_array().unwrap();
    assert!(url_block[2]["sql"]
        .as_str()
        .unwrap()
        .contains("INSERT INTO diting_import_url"));
    assert_eq!(url_block[4]["args"][0], json!("sub_4"));
    assert_eq!(
        url_block[4]["args"][1],
        json!(1),
        "enabled follows the subscription"
    );

    assert_eq!(plan.counts.type_skipped, 0);
    assert_eq!(plan.counts.cosmetic, 1);
    let counters = summary(&plan);
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
    let batches = batches_json(&plan.batches);
    assert_eq!(batches.len(), 2);
    assert_eq!(batches[0]["steps"].as_array().unwrap().len(), 6);
    assert_eq!(batches[1]["steps"].as_array().unwrap().len(), 6);
    let first = batches[0]["steps"][2]["sql"].as_str().unwrap();
    let second = batches[1]["steps"][2]["sql"].as_str().unwrap();
    assert_eq!(first.matches('?').count(), 20, "two rows of ten columns");
    assert_eq!(second.matches('?').count(), 10, "one row of ten columns");
    assert_eq!(
        batches[0]["steps"][4]["args"][1],
        json!(0),
        "source enabled flag"
    );
}

#[test]
fn a_staging_commit_swaps_every_source_table_atomically() {
    let plan = plan_json(&commit_source_plan("staging_sub_4", "sub_4", true));
    let steps = plan["steps"].as_array().unwrap();
    assert_eq!(
        steps.len(),
        12,
        "delete + copy + drop for each source table"
    );
    assert_eq!(
        steps[0]["sql"],
        json!("DELETE FROM block_rule_source WHERE source = ?")
    );
    assert_eq!(steps[0]["args"], json!(["sub_4"]));
    assert!(steps[1]["sql"]
        .as_str()
        .unwrap()
        .contains("SELECT ruleId, ?, ? FROM block_rule_source WHERE source = ?"));
    assert_eq!(steps[1]["args"], json!(["sub_4", 1, "staging_sub_4"]));
    assert_eq!(steps[2]["args"], json!(["staging_sub_4"]));
    assert_eq!(plan["orphans"].as_array().unwrap().len(), 4);
}

#[test]
fn a_hosts_dataset_drops_the_families_its_table_cannot_hold() {
    let parsed = parsed();
    let plan = import_plan(&parsed, "sub_4", "hosts", true, 1000, 1);
    let batches = batches_json(&plan.batches);
    let families: Vec<&str> = batches
        .iter()
        .map(|batch| batch["family"].as_str().unwrap())
        .collect();
    assert_eq!(families, vec!["block", "rewrite"]);
    assert_eq!(plan.counts.type_skipped, 4);
    assert_eq!(plan.counts.cosmetic, 0);
}

#[test]
fn a_rule_without_spaces_still_produces_an_empty_plan() {
    let empty = json!({});
    let plan = import_plan(&empty, "sub_4", "domain", true, 1000, 1);
    assert!(plan.batches.is_empty());
    assert_eq!(plan.counts.cosmetic, 0);
    assert_eq!(plan.counts.type_skipped, 0);
}

#[test]
fn table_names_come_from_one_place() {
    let tables = tables_plan();
    assert_eq!(tables["block"]["table"], json!("block_rule"));
    assert_eq!(tables["allow"]["sourceTable"], json!("allow_rule_source"));
    assert_eq!(tables["rewrite"]["table"], json!("rewrite_rule"));
    assert_eq!(tables["url"]["table"], json!("go_url_rule"));
    assert_eq!(tables["url"]["sourceTable"], json!("go_url_rule_source"));
    assert_eq!(
        tables["userSources"],
        json!(["useradd", "local_import", "local_hosts"])
    );
}

#[test]
fn a_source_sweep_deletes_source_rows_then_sweeps_orphans_in_pages() {
    let plan = plan_json(&remove_source_plan("sub_4"));
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
    let plan = plan_json(&set_source_enabled_plan("sub_4", false));
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

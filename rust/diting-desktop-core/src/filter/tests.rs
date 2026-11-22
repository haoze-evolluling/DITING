use std::path::{Path, PathBuf};

use chrono::{Local, Timelike};
use diting_desktop_api::config::{BlockingSchedule, FilterConfig, FilterList};

use super::*;

const A: u16 = 1;
const AAAA: u16 = 28;

fn unique_nanos() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(tag: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "diting-filter-{tag}-{}-{}",
            std::process::id(),
            unique_nanos()
        ));
        std::fs::create_dir_all(&path).expect("temp dir");
        Self { path }
    }

    fn write(&self, name: &str, contents: &str) {
        std::fs::write(self.path.join(name), contents).expect("write temp file");
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

fn base_config(dir: &TempDir) -> FilterConfig {
    FilterConfig {
        data_dir: dir.path().to_string_lossy().into_owned(),
        lists: Vec::new(),
        ..FilterConfig::default()
    }
}

fn schedule(start: &str, end: &str) -> BlockingSchedule {
    BlockingSchedule {
        id: format!("s-{start}-{end}"),
        name: "test".into(),
        enabled: true,
        weekdays: Vec::new(),
        start: start.into(),
        end: end.into(),
    }
}

fn active_now_window() -> (String, String) {
    let now = Local::now();
    let minute = now.hour() * 60 + now.minute();
    if minute < 23 * 60 + 59 {
        (
            format!("{:02}:{:02}", minute / 60, minute % 60),
            format!("{:02}:{:02}", (minute + 1) / 60, (minute + 1) % 60),
        )
    } else {
        ("23:59".to_string(), "00:01".to_string())
    }
}

#[test]
fn custom_rules_block_allow_important_denyallow_and_dnstype() {
    let dir = TempDir::new("custom");
    let mut config = base_config(&dir);
    config.custom_rules = vec![
        "||ads.test^".into(),
        "@@||safe.ads.test^".into(),
        "||important.test^$important".into(),
        "@@||important.test^$important".into(),
        "||excluded.test^$denyallow=trusted.excluded.test".into(),
        "||typed.test^$dnstype=AAAA".into(),
    ];
    let engine = RuleEngine::new(config);

    let blocked = engine.check("ads.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(blocked.blocked);
    assert_eq!(blocked.action, VerdictAction::Block);
    assert_eq!(blocked.reason, REASON_BLACKLIST);
    assert_eq!(blocked.list_name, "custom");
    assert!(blocked.matched_rule.contains("ads.test"));

    let allowed = engine.check("safe.ads.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(!allowed.blocked);
    assert_eq!(allowed.action, VerdictAction::Allow);
    assert_eq!(allowed.reason, REASON_WHITELIST);

    let important = engine.check("important.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert_eq!(important.action, VerdictAction::Allow);
    assert_eq!(important.reason, REASON_IMPORTANT_ALLOW);

    assert!(
        engine
            .check("trusted.excluded.test", A, DEFAULT_CLIENT_GROUP_ID)
            .action
            == VerdictAction::Pass
    );
    assert!(
        engine
            .check("excluded.test", A, DEFAULT_CLIENT_GROUP_ID)
            .blocked
    );

    assert!(
        !engine
            .check("typed.test", A, DEFAULT_CLIENT_GROUP_ID)
            .blocked
    );
    assert!(
        engine
            .check("typed.test", AAAA, DEFAULT_CLIENT_GROUP_ID)
            .blocked
    );
}

#[test]
fn services_and_groups_expand_into_block_rules() {
    let dir = TempDir::new("services");
    let mut config = base_config(&dir);
    config.blocked_services = vec!["youtube".into()];
    config.blocked_service_groups = vec!["messaging".into()];
    let engine = RuleEngine::new(config);

    let youtube = engine.check("www.youtube.com", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(youtube.blocked);
    assert_eq!(youtube.list_name, "service:youtube");

    let messaging = engine.check("t.me", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(messaging.blocked);
    assert_eq!(messaging.list_name, "service:telegram");

    let unrelated = engine.check("example.com", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(!unrelated.blocked);
}

#[test]
fn pause_disables_filtering_and_reports_remaining_time() {
    let dir = TempDir::new("pause");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["||ads.test^".into()];
    let engine = RuleEngine::new(config);

    assert!(engine.is_enabled());
    engine.set_paused(true, 60);
    assert!(!engine.is_enabled());
    let state = engine.pause_state();
    assert!(state.paused);
    assert!(state.remaining_sec >= 0);
    assert!(engine.paused_until().is_some());
    assert_eq!(
        engine.check("ads.test", A, DEFAULT_CLIENT_GROUP_ID).action,
        VerdictAction::Pass
    );

    engine.set_paused(false, 0);
    assert!(engine.is_enabled());
    assert!(engine.paused_until().is_none());
    assert!(engine.check("ads.test", A, DEFAULT_CLIENT_GROUP_ID).blocked);
}

#[test]
fn global_schedule_gates_the_engine() {
    let dir = TempDir::new("schedule");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["||ads.test^".into()];

    config.schedule_enabled = true;
    config.schedules = vec![schedule("00:00", "00:00")];
    let inactive = RuleEngine::new(config.clone());
    assert!(!inactive.is_enabled());
    let result = inactive.check("ads.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert_eq!(result.action, VerdictAction::Pass);
    assert_eq!(result.reason, REASON_SCHEDULE_INACTIVE);

    let (start, end) = active_now_window();
    config.schedules = vec![schedule(&start, &end)];
    let active = RuleEngine::new(config);
    assert!(active.is_enabled());
    assert!(active.check("ads.test", A, DEFAULT_CLIENT_GROUP_ID).blocked);
}

#[test]
fn per_group_schedule_overrides_global() {
    let dir = TempDir::new("group-schedule");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["||ads.test^".into()];
    config.schedule_enabled = true;
    config.schedules = vec![schedule("00:00", "00:00")];

    let (start, end) = active_now_window();
    let engine = RuleEngine::new(config);
    engine.set_groups(GroupConfig {
        enabled: true,
        groups: vec![ClientGroup {
            id: "kids".into(),
            enabled: true,
            schedule_enabled: true,
            schedules: vec![schedule(&start, &end)],
            ..ClientGroup::default()
        }],
    });

    assert!(engine
        .check("ads.test", A, DEFAULT_CLIENT_GROUP_ID)
        .reason
        .eq(REASON_SCHEDULE_INACTIVE));
    assert!(engine.check("ads.test", A, "kids").blocked);
}

#[test]
fn allowlist_only_blocks_unmatched_queries() {
    let dir = TempDir::new("allowlist-only");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["@@||allowed.test^".into()];
    config.allowlist_only = true;
    let engine = RuleEngine::new(config);

    assert_eq!(
        engine
            .check("allowed.test", A, DEFAULT_CLIENT_GROUP_ID)
            .action,
        VerdictAction::Allow
    );
    let blocked = engine.check("unmatched.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(blocked.blocked);
    assert_eq!(blocked.reason, REASON_ALLOWLIST_ONLY);
}

#[test]
fn rewrite_rules_produce_answers_and_nodata() {
    let dir = TempDir::new("rewrite");
    let mut config = base_config(&dir);
    config.custom_rules = vec![
        "||r.test^$dnsrewrite=1.2.3.4".into(),
        "||refused.test^$dnsrewrite=REFUSED".into(),
    ];
    let engine = RuleEngine::new(config);

    let answer = engine.check("r.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert_eq!(answer.action, VerdictAction::Rewrite);
    assert_eq!(answer.reason, REASON_DNSREWRITE);
    assert!(!answer.blocked);
    let rewritten = answer.rewritten.expect("rewrite result");
    assert_eq!(rewritten.rcode, 0);
    assert_eq!(rewritten.records.len(), 1);
    assert_eq!(rewritten.records[0].kind, "A");
    assert_eq!(rewritten.records[0].value, "1.2.3.4");
    assert_eq!(rewritten.records[0].ttl, REWRITE_TTL);
    assert_eq!(rewritten.summary.len(), 1);

    let nodata = engine.check("r.test", AAAA, DEFAULT_CLIENT_GROUP_ID);
    assert_eq!(nodata.action, VerdictAction::Rewrite);
    assert!(nodata.rewritten.expect("nodata result").records.is_empty());

    let refused = engine.check("refused.test", A, DEFAULT_CLIENT_GROUP_ID);
    let refused = refused.rewritten.expect("refused result");
    assert_eq!(refused.rcode, 5);
    assert!(refused.records.is_empty());
}

#[test]
fn response_recheck_catches_blocked_alias_targets() {
    let dir = TempDir::new("response");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["||evil.test^".into()];
    let engine = RuleEngine::new(config);

    let cname = engine.check_response(
        "good.test",
        A,
        DEFAULT_CLIENT_GROUP_ID,
        &[ResponseRecord::cname("good.test", "evil.test")],
    );
    assert!(cname.blocked);
    assert_eq!(cname.reason, REASON_RESPONSE_BLOCKED);

    let owner = engine.check_response(
        "good.test",
        A,
        DEFAULT_CLIENT_GROUP_ID,
        &[ResponseRecord::address(
            "cdn.evil.test",
            ResponseRecordKind::A,
        )],
    );
    assert!(owner.blocked);

    let clean = engine.check_response(
        "good.test",
        A,
        DEFAULT_CLIENT_GROUP_ID,
        &[ResponseRecord::address("good.test", ResponseRecordKind::A)],
    );
    assert!(!clean.blocked);
}

#[test]
fn bogus_nxdomain_matches_ipv4_and_ipv6_sets() {
    let dir = TempDir::new("bogus");
    let mut config = base_config(&dir);
    config.bogus_nx_domain = true;
    config.bogus_nx_domain_networks = vec!["203.0.113.0/24".into(), "::1".into()];
    let engine = RuleEngine::new(config);

    let hit = engine
        .bogus_nxdomain(&["203.0.113.9".parse().unwrap()])
        .expect("ipv4 hit");
    assert_eq!(hit.ip, "203.0.113.9".parse::<std::net::IpAddr>().unwrap());
    assert!(engine.bogus_nxdomain(&["::1".parse().unwrap()]).is_some());
    assert!(engine
        .bogus_nxdomain(&["8.8.8.8".parse().unwrap()])
        .is_none());
    assert_eq!(engine.bogus_nxdomain_hits(), 2);

    let mut disabled = base_config(&TempDir::new("bogus-off"));
    disabled.bogus_nx_domain = false;
    disabled.bogus_nx_domain_networks = vec!["203.0.113.0/24".into()];
    let engine = RuleEngine::new(disabled);
    assert!(engine
        .bogus_nxdomain(&["203.0.113.9".parse().unwrap()])
        .is_none());
}

#[tokio::test]
async fn local_list_fetch_populates_the_cache_and_index() {
    let dir = TempDir::new("fetch");
    let source = dir.path().join("source.txt");
    std::fs::write(&source, "||local.test^\n").expect("source");

    let engine = RuleEngine::new(base_config(&dir));
    assert!(
        !engine
            .check("local.test", A, DEFAULT_CLIENT_GROUP_ID)
            .blocked
    );

    engine
        .add_list(FilterList {
            id: "local".into(),
            name: "Local".into(),
            url: source.to_string_lossy().into_owned(),
            enabled: true,
            ..FilterList::default()
        })
        .await
        .expect("add list");

    let blocked = engine.check("local.test", A, DEFAULT_CLIENT_GROUP_ID);
    assert!(blocked.blocked);
    assert_eq!(blocked.list_name, "local");

    let lists = engine.config().lists;
    let stored = lists.iter().find(|list| list.id == "local").expect("list");
    assert_eq!(stored.rules_count, 1);
    assert_eq!(stored.last_status, "ok");
    assert!(!stored.checksum.is_empty());

    engine.refresh_list("local").await.expect("refresh");
    engine.delete_list("local").await.expect("delete");
    assert!(!engine.config().lists.iter().any(|list| list.id == "local"));
    assert!(
        !engine
            .check("local.test", A, DEFAULT_CLIENT_GROUP_ID)
            .blocked
    );
}

#[test]
fn group_matchers_only_include_selected_lists() {
    let dir = TempDir::new("group-lists");
    dir.write("one.txt", "||one.test^\n");
    dir.write("two.txt", "||two.test^\n");

    let mut config = base_config(&dir);
    config.custom_rules = vec!["||custom.test^".into()];
    config.lists = vec![
        FilterList {
            id: "one".into(),
            name: "One".into(),
            url: "unused".into(),
            enabled: true,
            ..FilterList::default()
        },
        FilterList {
            id: "two".into(),
            name: "Two".into(),
            url: "unused".into(),
            enabled: true,
            ..FilterList::default()
        },
    ];
    let engine = RuleEngine::new(config);
    engine.set_groups(GroupConfig {
        enabled: true,
        groups: vec![ClientGroup {
            id: "kids".into(),
            enabled: true,
            rule_list_ids: vec!["one".into()],
            block_mode: "nxdomain".into(),
            ..ClientGroup::default()
        }],
    });

    assert!(engine.check("two.test", A, DEFAULT_CLIENT_GROUP_ID).blocked);
    assert!(engine.check("one.test", A, "kids").blocked);
    assert!(!engine.check("two.test", A, "kids").blocked);
    assert!(engine.check("custom.test", A, "kids").blocked);
    assert_eq!(engine.group_block_mode("kids").as_deref(), Some("nxdomain"));
    assert_eq!(engine.block_response_config("kids").block_mode, "nxdomain");
    assert_eq!(
        engine.block_response_config("default").block_mode,
        "null_ip"
    );
}

#[test]
fn stats_track_queries_rules_and_lists() {
    let dir = TempDir::new("stats");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["||ads.test^".into(), "@@||ok.test^".into()];
    let engine = RuleEngine::new(config);

    engine.check("ads.test", A, DEFAULT_CLIENT_GROUP_ID);
    engine.check("ok.test", A, DEFAULT_CLIENT_GROUP_ID);
    engine.check("other.test", A, DEFAULT_CLIENT_GROUP_ID);
    let stats = engine.stats();
    assert_eq!(stats.total_queries, 3);
    assert_eq!(stats.blocked_queries, 1);
    assert_eq!(stats.allowed_queries, 1);
    assert!((stats.block_rate - 100.0 / 3.0).abs() < 0.001);
    assert_eq!(stats.total_rules, 2);
    assert!(stats.schedule_active);
    assert!(!stats.paused);

    engine.record_verdict(&CheckHostResult::pass());
    assert_eq!(engine.stats().total_queries, 4);
}

#[test]
fn check_host_is_read_only() {
    let dir = TempDir::new("check-host");
    let mut config = base_config(&dir);
    config.custom_rules = vec!["||ads.test^".into()];
    let engine = RuleEngine::new(config);

    assert!(engine.check_host("ADS.test.", A).blocked);
    assert_eq!(engine.stats().total_queries, 0);
    engine.set_paused(true, 60);
    assert!(engine.check_host("ads.test", A).blocked);
}

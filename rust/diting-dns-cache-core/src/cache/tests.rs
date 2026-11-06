//! Container tests: the Go behaviours that used to be asserted by `dns_cache_test.go`,
//! `dns_cache_snapshot_test.go` and the LRU regression in `dns_low_regression_test.go`.

use std::sync::Arc;
use std::time::{Duration, Instant};

use super::*;

const CLASS_IN: u16 = 1;
const TYPE_A: u16 = 1;
const TYPE_AAAA: u16 = 28;

fn name_wire(name: &str) -> Vec<u8> {
    let trimmed = name.trim_end_matches('.');
    let mut out = Vec::new();
    if trimmed.is_empty() {
        out.push(0);
        return out;
    }
    for label in trimmed.split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out
}

fn query(name: &str, qtype: u16) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x1234u16.to_be_bytes());
    out.extend(0x0100u16.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire(name));
    out.extend(qtype.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    out
}

fn answer(name: &str, ttl: u32, rcode: u8, ips: &[[u8; 4]]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x2222u16.to_be_bytes());
    out.extend((0x8180u16 | u16::from(rcode)).to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend((ips.len() as u16).to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire(name));
    out.extend(TYPE_A.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    for ip in ips {
        out.extend(name_wire(name));
        out.extend(TYPE_A.to_be_bytes());
        out.extend(CLASS_IN.to_be_bytes());
        out.extend(ttl.to_be_bytes());
        out.extend(4u16.to_be_bytes());
        out.extend_from_slice(ip);
    }
    out
}

fn config() -> Config {
    Config {
        enabled: true,
        ..Config::default()
    }
    .normalized()
}

fn store(cache: &Cache, name: &str, ttl: u32, ips: &[[u8; 4]]) -> bool {
    let request = query(name, TYPE_A);
    let response = answer(name, ttl, 0, ips);
    cache.put(&request, &response)
}

/// Rewrites the deadlines of the entry behind `name` so a test can travel in time.
fn force_expired(cache: &Cache, name: &str, stale_seconds: i64) {
    let request = query(name, TYPE_A);
    let (buffer, parts) = build_key(&request).expect("key");
    let key = &buffer[..parts.key_len];
    let now = Instant::now();
    let mut shard = write_guard(&cache.shards[shard_index(key)]);
    let entry = shard.entries.get_mut(key).expect("entry");
    entry.expires_at = now - Duration::from_secs(1);
    entry.expires_at_ms = now_wall_ms() - 1000;
    entry.stale_until = now + Duration::from_secs(stale_seconds.max(0) as u64);
}

#[test]
fn put_then_get_rewrites_id_ttl_and_metadata() {
    let cache = Cache::new(config());
    let request = query("zerocopy.example.", TYPE_A);
    let response = answer("zerocopy.example.", 300, 0, &[[1, 2, 3, 4], [5, 6, 7, 8]]);
    assert!(cache.put(&request, &response));

    let mut second = query("zerocopy.example.", TYPE_A);
    second[0] = 0x88;
    second[1] = 0x88;
    let hit = cache.get(&second, true).expect("hit");
    assert!(!hit.stale);
    assert!(!hit.is_negative);
    assert_eq!(hit.ip_list, vec!["1.2.3.4", "5.6.7.8"]);
    assert_eq!(hit.resolved_ips, "1.2.3.4,5.6.7.8");
    assert!(hit.chain_targets.is_empty());
    assert_eq!(&hit.wire[0..2], &[0x88, 0x88]);
    assert!(hit.wire.len() >= response.len());
    let stats = cache.stats();
    assert_eq!((stats.total_hits, stats.total_misses), (1, 0));
    cache.close();
}

#[test]
fn truncation_disables_caching() {
    let cache = Cache::new(config());
    let request = query("truncated.example.", TYPE_A);
    let mut response = answer("truncated.example.", 300, 0, &[[1, 2, 3, 4]]);
    response[2] |= 0x02; // TC bit
    assert!(!cache.put(&request, &response));
    assert!(cache.get(&request, true).is_none());
    assert_eq!(cache.stats().total_misses, 1);
    cache.close();
}

#[test]
fn negative_answers_are_cached_and_flagged() {
    let cache = Cache::new(config());
    let request = query("nonexistent.example.", TYPE_A);
    let response = answer("nonexistent.example.", 10, RCODE_NAME_ERROR, &[]);
    assert!(cache.put(&request, &response));
    let hit = cache.get(&request, true).expect("hit");
    assert!(hit.is_negative);
    assert_eq!(hit.wire[3] & 0x0f, RCODE_NAME_ERROR);
    assert_eq!(cache.stats().negative_hits, 1);

    // NODATA (NOERROR with no answers) takes the same path.
    let request = query("nodata.example.", TYPE_AAAA);
    let response = answer("nodata.example.", 10, 0, &[]);
    assert!(cache.put(&request, &response));
    let hit = cache.get(&request, true).expect("hit");
    assert!(hit.is_negative);
    cache.close();
}

#[test]
fn max_ttl_is_clamped_to_the_policy() {
    let mut config = config();
    config.mode = crate::policy::TtlMode::LimitMaxTtl;
    config.max_ttl_seconds = 60;
    let cache = Cache::new(config);
    assert!(store(&cache, "clamp.example.", 3600, &[[1, 2, 3, 4]]));
    let request = query("clamp.example.", TYPE_A);
    let (buffer, parts) = build_key(&request).expect("key");
    let key = &buffer[..parts.key_len];
    let shard = read_guard(&cache.shards[shard_index(key)]);
    let entry = shard.entries.get(key).expect("entry");
    assert_eq!(entry.created_at_ms + 60_000, entry.expires_at_ms);
    drop(shard);
    cache.close();
}

#[test]
fn fixed_ttl_overrides_the_upstream_value() {
    let mut config = config();
    config.mode = crate::policy::TtlMode::FixedTtl;
    config.fixed_ttl_seconds = 120;
    let cache = Cache::new(config);
    assert!(store(&cache, "fixed.example.", 5, &[[1, 2, 3, 4]]));
    let request = query("fixed.example.", TYPE_A);
    let hit = cache.get(&request, true).expect("hit");
    let ttl = ttl_at(&hit.wire, "fixed.example.");
    assert!((119..=120).contains(&ttl), "ttl was {ttl}");
    cache.close();
}

fn ttl_at(wire: &[u8], name: &str) -> u32 {
    let offset = 12 + name_wire(name).len() + 4 + name_wire(name).len() + 4;
    u32::from_be_bytes([
        wire[offset],
        wire[offset + 1],
        wire[offset + 2],
        wire[offset + 3],
    ])
}

#[test]
fn stale_fallback_serves_one_second_and_counts() {
    let mut config = config();
    config.stale_fallback_enabled = true;
    config.stale_fallback_seconds = 600;
    let cache = Cache::new(config.clone());
    assert!(store(&cache, "stale.example.", 300, &[[1, 1, 1, 1]]));
    force_expired(&cache, "stale.example.", 600);

    let request = query("stale.example.", TYPE_A);
    let hit = cache.get(&request, true).expect("stale candidate");
    assert!(hit.stale);
    assert_eq!(ttl_at(&hit.wire, "stale.example."), 1);
    assert_eq!(cache.stats().stale_hits, 1);

    // Without stale fallback the same entry is a miss and is evicted lazily.
    let mut plain = config;
    plain.stale_fallback_enabled = false;
    plain.stale_fallback_seconds = 0;
    let cache = Cache::new(plain);
    assert!(store(&cache, "stale.example.", 300, &[[1, 1, 1, 1]]));
    force_expired(&cache, "stale.example.", 0);
    assert!(cache.get(&request, true).is_none());
    assert_eq!(cache.stats().entry_count, 0);
    cache.close();
}

#[test]
fn full_expiry_is_a_lazy_miss() {
    let cache = Cache::new(config());
    assert!(store(&cache, "expired.example.", 300, &[[1, 2, 3, 4]]));
    force_expired(&cache, "expired.example.", -1);
    assert!(cache
        .get(&query("expired.example.", TYPE_A), true)
        .is_none());
    assert_eq!(cache.stats().entry_count, 0);
    assert_eq!(cache.stats().evictions, 0, "lazy expiry is not an eviction");
    cache.close();
}

#[test]
fn refresh_slot_is_exclusive() {
    let cache = Cache::new(config());
    let request = query("refresh.example.", TYPE_A);
    assert!(store(&cache, "refresh.example.", 300, &[[1, 2, 3, 4]]));
    assert!(cache.refresh_begin(&request));
    assert!(!cache.refresh_begin(&request));
    cache.refresh_done(&request);
    assert!(cache.refresh_begin(&request));
    cache.refresh_done(&request);

    let unknown = query("unknown.example.", TYPE_A);
    assert!(!cache.refresh_begin(&unknown));
    cache.close();
}

#[test]
fn single_flight_recheck_does_not_count() {
    let cache = Cache::new(config());
    let request = query("once.example.", TYPE_A);
    assert!(cache.get(&request, true).is_none());
    assert!(store(&cache, "once.example.", 300, &[[192, 0, 2, 1]]));
    // The re-check must find the entry without touching the counters.
    assert!(cache.get(&request, false).is_some());
    let stats = cache.stats();
    assert_eq!((stats.total_hits, stats.total_misses), (0, 1));
    cache.close();
}

#[test]
fn a_stale_recheck_does_not_count_as_a_stale_hit() {
    let mut config = config();
    config.stale_fallback_enabled = true;
    config.stale_fallback_seconds = 600;
    let cache = Cache::new(config);
    assert!(store(&cache, "recheck.example.", 300, &[[192, 0, 2, 9]]));
    force_expired(&cache, "recheck.example.", 600);

    let request = query("recheck.example.", TYPE_A);
    // The background refresh re-checks without serving: no counter may move.
    assert!(cache.get(&request, false).is_some());
    assert_eq!(cache.stats().stale_hits, 0);
    assert!(cache.get(&request, true).is_some());
    assert_eq!(cache.stats().stale_hits, 1);
    cache.close();
}

#[test]
fn disabling_the_cache_releases_entries() {
    let cache = Cache::new(config());
    assert!(store(&cache, "off.example.", 300, &[[192, 0, 2, 2]]));
    assert_eq!(cache.stats().entry_count, 1);
    cache.update_policy(Config {
        enabled: false,
        ..Config::default()
    });
    assert_eq!(cache.stats().entry_count, 0);
    cache.close();
}

#[test]
fn disabled_cache_stores_and_looks_up_nothing() {
    let cache = Cache::new(Config::default());
    assert!(!store(&cache, "disabled.example.", 300, &[[192, 0, 2, 3]]));
    assert!(cache
        .get(&query("disabled.example.", TYPE_A), true)
        .is_none());
    assert_eq!(cache.stats().total_misses, 0);
    assert!(!cache.stats().enabled);
    cache.close();
}

#[test]
fn clear_drops_every_shard_and_keeps_the_lru_consistent() {
    let cache = Cache::new(config());
    for index in 0..128 {
        let name = format!("clear-{index}.example.");
        assert!(store(&cache, &name, 300, &[[10, 0, 0, 1]]));
    }
    cache.clear();
    assert_eq!(cache.stats().entry_count, 0);
    // The shard must stay usable: inserting after a clear continues from a defined state.
    assert!(store(&cache, "after-clear.example.", 300, &[[10, 0, 0, 2]]));
    assert!(cache
        .get(&query("after-clear.example.", TYPE_A), true)
        .is_some());
    cache.close();
}

#[test]
fn shards_evict_the_least_recently_used_entry() {
    let mut config = config();
    config.mode = crate::policy::TtlMode::FollowDnsTtl;
    let cache = Cache::new(config);
    // 4096 entries is the budget; the 4097th distinct key evicts one per full shard.
    for index in 0..DEFAULT_MAX_ENTRIES + 64 {
        let name = format!("bulk-{index}.example.");
        assert!(store(&cache, &name, 300, &[[10, 0, 0, 1]]));
    }
    let stats = cache.stats();
    assert!(stats.entry_count <= stats.max_entries);
    assert!(stats.evictions > 0);
    cache.close();
}

#[test]
fn snapshot_is_hot_first_and_capped() {
    let cache = Cache::new(config());
    for index in 0..3 {
        let name = format!("snapshot-{index}.example.");
        let request = query(&name, TYPE_A);
        assert!(store(&cache, &name, 300, &[[93, 184, 216, 34]]));
        for _ in 0..index {
            cache.get(&request, true);
        }
    }
    let entries = cache.snapshot(10);
    assert_eq!(entries.len(), 3);
    assert_eq!(entries[0].query_name, b"snapshot-2.example");
    assert_eq!(entries[0].hit_count, 2);
    assert!(entries[0].response_size > 0);
    assert!(entries[0].last_hit_at_ms > 0);
    assert_eq!(cache.snapshot(1).len(), 1);

    // An expired entry is filtered out of the projection.
    force_expired(&cache, "snapshot-2.example.", -1);
    let entries = cache.snapshot(10);
    assert!(entries
        .iter()
        .all(|entry| entry.query_name != b"snapshot-2.example"));
    cache.close();
}

#[test]
fn sweeper_reclaims_only_entries_past_the_stale_deadline() {
    let cache = Cache::new(config());
    assert!(store(&cache, "sweep-live.example.", 300, &[[10, 0, 0, 3]]));
    assert!(store(&cache, "sweep-dead.example.", 300, &[[10, 0, 0, 4]]));
    force_expired(&cache, "sweep-dead.example.", -1);
    cache.sweep_expired(Instant::now());
    assert_eq!(cache.stats().entry_count, 1);
    assert_eq!(cache.stats().evictions, 1);
    assert!(cache
        .get(&query("sweep-live.example.", TYPE_A), true)
        .is_some());
    cache.close();
}

#[test]
fn concurrent_workers_share_the_container() {
    let cache = Cache::new(config());
    let mut handles = Vec::new();
    for worker in 0..8 {
        let cache = Arc::clone(&cache);
        handles.push(std::thread::spawn(move || {
            for index in 0..64 {
                let name = format!("worker-{}.example.", worker % 5);
                let request = query(&name, TYPE_A);
                if index % 2 == 0 {
                    cache.get(&request, true);
                } else {
                    let response = answer(&name, 60, 0, &[[10, 0, 0, index as u8]]);
                    cache.put(&request, &response);
                }
            }
        }));
    }
    for handle in handles {
        handle.join().expect("worker");
    }
    let stats = cache.stats();
    assert!(stats.total_hits + stats.total_misses > 0);
    cache.close();
}

#[test]
fn same_key_replaces_the_previous_entry() {
    let cache = Cache::new(config());
    assert!(store(&cache, "replace.example.", 300, &[[10, 0, 0, 5]]));
    assert!(store(&cache, "replace.example.", 300, &[[10, 0, 0, 6]]));
    assert_eq!(cache.stats().entry_count, 1);
    let hit = cache
        .get(&query("replace.example.", TYPE_A), true)
        .expect("hit");
    assert_eq!(hit.ip_list, vec!["10.0.0.6"]);
    cache.close();
}

#[test]
fn malformed_queries_and_responses_are_rejected() {
    let cache = Cache::new(config());
    assert!(!cache.put(&[0u8; 4], &[0u8; 4]));
    assert!(cache.get(&[0u8; 4], true).is_none());
    // A response the wire parser cannot walk is not a cache candidate.
    assert!(!cache.put(&query("bad.example.", TYPE_A), &[0u8; 11]));
    cache.close();
}

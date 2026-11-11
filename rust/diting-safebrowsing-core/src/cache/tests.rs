//! Behaviour ported from the Go `hashCache` cases: dedupe by prefix, negative answers cached,
//! expiry, size limit and LRU order. Time is injected, so nothing here sleeps.

use super::*;
use crate::hash::HASH_SIZE;

fn hash(seed: u8) -> HostnameHash {
    [seed; HASH_SIZE]
}

fn hash_with_prefix(prefix: [u8; 2], tail: u8) -> HostnameHash {
    let mut value = [tail; HASH_SIZE];
    value[0] = prefix[0];
    value[1] = prefix[1];
    value
}

#[test]
fn fresh_cache_asks_for_every_prefix() {
    let mut cache = HashCache::new(16, 1_000);
    let lookup = cache.lookup(&[hash(1), hash(2)], 0);
    assert!(!lookup.found);
    assert!(!lookup.blocked);
    assert_eq!(lookup.need_query, vec![hash(1), hash(2)]);
}

#[test]
fn duplicate_prefixes_are_asked_once() {
    let mut cache = HashCache::new(16, 1_000);
    let first = hash_with_prefix([7, 7], 1);
    let second = hash_with_prefix([7, 7], 2);
    let lookup = cache.lookup(&[first, second], 0);
    assert!(!lookup.found);
    assert_eq!(lookup.need_query, vec![first]);
}

#[test]
fn stored_hit_is_reported_as_blocked() {
    let mut cache = HashCache::new(16, 1_000);
    cache.store(&[hash(1)], &[hash(1)], 100);
    let lookup = cache.lookup(&[hash(1)], 200);
    assert!(lookup.found);
    assert!(lookup.blocked);
    assert!(lookup.need_query.is_empty());
}

#[test]
fn empty_answer_is_cached_too() {
    let mut cache = HashCache::new(16, 1_000);
    cache.store(&[hash(1)], &[], 100);
    let lookup = cache.lookup(&[hash(1)], 200);
    assert!(lookup.found);
    assert!(!lookup.blocked);
    assert!(lookup.need_query.is_empty());
}

#[test]
fn digests_of_other_prefixes_are_not_attributed() {
    let mut cache = HashCache::new(16, 1_000);
    cache.store(
        &[hash_with_prefix([1, 2], 0)],
        &[hash_with_prefix([3, 4], 0)],
        100,
    );
    let lookup = cache.lookup(&[hash_with_prefix([1, 2], 0)], 200);
    assert!(lookup.found);
    assert!(!lookup.blocked);
}

#[test]
fn expiry_is_strictly_after_the_deadline() {
    let mut cache = HashCache::new(16, 500);
    cache.store(&[hash(1)], &[hash(1)], 1_000);

    let at_deadline = cache.lookup(&[hash(1)], 1_500);
    assert!(at_deadline.found, "the deadline itself is still live");

    let after = cache.lookup(&[hash(1)], 1_501);
    assert!(!after.found);
    assert_eq!(after.need_query, vec![hash(1)]);
    assert_eq!(cache.len(), 0, "the expired entry is dropped");
}

#[test]
fn store_refreshes_the_deadline() {
    let mut cache = HashCache::new(16, 500);
    cache.store(&[hash(1)], &[hash(1)], 1_000);
    cache.store(&[hash(1)], &[hash(1)], 1_400);
    assert!(cache.lookup(&[hash(1)], 1_800).found);
    assert!(!cache.lookup(&[hash(1)], 1_901).found);
}

#[test]
fn least_recently_used_entry_is_evicted() {
    let mut cache = HashCache::new(2, 60_000);
    cache.store(&[hash(1)], &[hash(1)], 10);
    cache.store(&[hash(2)], &[hash(2)], 20);

    // A hit promotes hash(1), so hash(2) becomes the eviction candidate.
    assert!(cache.lookup(&[hash(1)], 30).blocked);
    cache.store(&[hash(3)], &[hash(3)], 40);

    assert_eq!(cache.len(), 2);
    assert!(!cache.lookup(&[hash(2)], 50).found, "hash(2) was evicted");
    assert!(cache.lookup(&[hash(1)], 60).found);
    assert!(cache.lookup(&[hash(3)], 70).found);
}

#[test]
fn capacity_is_bounded() {
    let mut cache = HashCache::new(4, 60_000);
    for seed in 1..=6u8 {
        cache.store(&[hash(seed)], &[hash(seed)], i64::from(seed));
    }
    assert_eq!(cache.len(), 4);
}

#[test]
fn non_positive_configuration_falls_back_to_defaults() {
    let cache = HashCache::new(0, 0);
    assert_eq!(cache.size, DEFAULT_CACHE_SIZE);
    assert_eq!(cache.ttl_ms, DEFAULT_CACHE_TTL_MS);

    let negative = HashCache::new(-5, -5);
    assert_eq!(negative.size, DEFAULT_CACHE_SIZE);
    assert_eq!(negative.ttl_ms, DEFAULT_CACHE_TTL_MS);
}

#[test]
fn empty_query_neither_stores_nor_evicts() {
    let mut cache = HashCache::new(1, 60_000);
    cache.store(&[hash(1)], &[hash(1)], 0);
    cache.store(&[], &[hash(2)], 10);
    assert_eq!(cache.len(), 1);
    assert!(cache.lookup(&[hash(1)], 20).found);
}

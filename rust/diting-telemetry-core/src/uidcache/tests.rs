use super::*;

fn addr(last: u8) -> Addr {
    Addr::V4([10, 0, 0, last])
}

fn key(app_port: i32) -> FlowKey {
    FlowKey::new(addr(2), app_port, Addr::V4([1, 1, 1, 1]), 443, 6)
}

#[test]
fn a_positive_flow_uid_lives_for_two_seconds() {
    let cache = FlowUidCache::new();
    cache.store(key(40_000), 10_123, 0);
    assert_eq!(cache.len(), 1);
    assert_eq!(cache.lookup(&key(40_000), 1_999_999_999), Some(10_123));
    assert_eq!(cache.lookup(&key(40_000), 2_000_000_000), None);
    // The expired row is still counted, exactly like the Go map.
    assert_eq!(cache.len(), 1);
}

#[test]
fn a_negative_flow_uid_lives_for_half_a_second() {
    let cache = FlowUidCache::new();
    for (offset, uid) in [-1, 0, -42].into_iter().enumerate() {
        let app_port = 1000 + offset as i32;
        cache.store(key(app_port), uid, 0);
        assert_eq!(cache.lookup(&key(app_port), 499_999_999), Some(uid));
        assert_eq!(cache.lookup(&key(app_port), 500_000_000), None);
    }
}

#[test]
fn the_flow_key_truncates_like_the_go_struct_assignment() {
    // Ports go through uint16, the protocol through uint8.
    assert_eq!(key(70_000), key(70_000 - 65_536));
    let wide = FlowKey::new(addr(2), 1, addr(9), 2, 261);
    let narrow = FlowKey::new(addr(2), 1, addr(9), 2, 5);
    assert_eq!(wide, narrow);
    // The two address widths stay distinct, as netip.Addr made them.
    assert_ne!(
        Addr::from_bytes(&[0, 0, 0, 0]).unwrap(),
        Addr::from_bytes(&[0u8; 16]).unwrap()
    );
    assert!(Addr::from_bytes(&[1, 2, 3]).is_none());
    assert!(Addr::from_bytes(&[]).is_none());
}

#[test]
fn the_flow_cache_prunes_expired_rows_before_resetting() {
    let cache = FlowUidCache::new();
    for index in 0..FLOW_UID_CACHE_MAX_ENTRIES {
        cache.store(key(index as i32), 1000, 0);
    }
    assert_eq!(cache.len(), FLOW_UID_CACHE_MAX_ENTRIES as u32);

    // Still inside every TTL: nothing to prune, so the whole map is dropped.
    cache.store(key(100_000), 2000, 1_000_000_000);
    assert_eq!(cache.len(), 1);
    assert_eq!(cache.lookup(&key(100_000), 1_000_000_001), Some(2000));

    // Past every TTL: the prune frees the room, so the live rows are not dropped.
    for index in 0..FLOW_UID_CACHE_MAX_ENTRIES - 1 {
        cache.store(key(index as i32), 1000, 0);
    }
    assert_eq!(cache.len(), FLOW_UID_CACHE_MAX_ENTRIES as u32);
    cache.store(key(200_000), 3000, 3_000_000_000);
    assert_eq!(cache.len(), 1);
    assert_eq!(cache.lookup(&key(200_000), 3_000_000_001), Some(3000));
}

#[test]
fn a_package_name_lives_for_a_minute() {
    let cache = UidPackageCache::new();
    cache.store(10_001, "com.example", 0);
    assert_eq!(
        cache.lookup(10_001, 59_999_999_999),
        Some("com.example".into())
    );
    assert_eq!(cache.lookup(10_001, 60_000_000_000), None);
    assert_eq!(cache.lookup(10_002, 0), None);
}

#[test]
fn empty_package_names_are_not_cached() {
    let cache = UidPackageCache::new();
    cache.store(10_001, "", 0);
    assert_eq!(cache.len(), 0);
    assert_eq!(cache.lookup(10_001, 0), None);
}

#[test]
fn the_package_cache_resets_at_its_cap_without_pruning() {
    let cache = UidPackageCache::new();
    for uid in 0..UID_PACKAGE_CACHE_MAX_ENTRIES {
        cache.store(uid as i32, "com.example", 0);
    }
    assert_eq!(cache.len(), UID_PACKAGE_CACHE_MAX_ENTRIES as u32);

    // No prune pass: the whole map is dropped even though every row is still live.
    cache.store(9999, "com.late", 1);
    assert_eq!(cache.len(), 1);
    assert_eq!(cache.lookup(0, 1), None);
    assert_eq!(cache.lookup(9999, 1), Some("com.late".into()));
}

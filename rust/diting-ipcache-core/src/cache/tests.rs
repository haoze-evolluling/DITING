use super::*;

#[test]
fn basic_put_and_get() {
    let cache = IpDomainCache::new(4);
    cache.put("203.0.113.1", "one.example");
    assert_eq!(cache.get("203.0.113.1").as_deref(), Some("one.example"));
    assert_eq!(cache.get("203.0.113.2"), None);
    assert_eq!(cache.len(), 1);
    assert!(!cache.is_empty());
}

#[test]
fn empty_keys_are_ignored_on_both_sides() {
    let cache = IpDomainCache::new(4);
    cache.put("", "ignored.example");
    cache.put("203.0.113.1", "");
    assert_eq!(cache.len(), 0);
    assert_eq!(cache.get(""), None);
    assert_eq!(cache.get("203.0.113.1"), None);
}

#[test]
fn a_put_updates_the_domain_in_place() {
    let cache = IpDomainCache::new(4);
    cache.put("203.0.113.1", "old.example");
    cache.put("203.0.113.1", "new.example");
    assert_eq!(cache.get("203.0.113.1").as_deref(), Some("new.example"));
    assert_eq!(cache.len(), 1);
}

#[test]
fn a_read_never_promotes() {
    let cache = IpDomainCache::new(2);
    cache.put("a", "1");
    cache.put("b", "2");
    // Reading `a` must not make it the most recent write: `c` still evicts `a`.
    assert_eq!(cache.get("a").as_deref(), Some("1"));
    cache.put("c", "3");
    assert_eq!(cache.get("a"), None);
    assert_eq!(cache.get("b").as_deref(), Some("2"));
    assert_eq!(cache.get("c").as_deref(), Some("3"));
    assert_eq!(cache.len(), 2);
}

#[test]
fn a_repeated_put_moves_the_entry_to_the_front() {
    let cache = IpDomainCache::new(2);
    cache.put("a", "1");
    cache.put("b", "2");
    cache.put("a", "1"); // touch, even with the same value
    cache.put("c", "3");
    assert_eq!(cache.get("b"), None);
    assert_eq!(cache.get("a").as_deref(), Some("1"));
    assert_eq!(cache.get("c").as_deref(), Some("3"));
}

#[test]
fn a_capacity_of_one_keeps_only_the_newest() {
    let cache = IpDomainCache::new(1);
    cache.put("a", "1");
    cache.put("b", "2");
    assert_eq!(cache.get("a"), None);
    assert_eq!(cache.get("b").as_deref(), Some("2"));
    assert_eq!(cache.len(), 1);
}

#[test]
fn non_positive_capacities_use_the_default_2048() {
    for capacity in [0, -1, -2048] {
        let cache = IpDomainCache::new(capacity);
        for index in 0..DEFAULT_MAX_SIZE {
            cache.put(
                &format!("10.0.{}.{}", index / 256, index % 256),
                "kept.example",
            );
        }
        assert_eq!(cache.len(), DEFAULT_MAX_SIZE as u32);
        // The 2049th insert evicts the least-recently-written key and leaves the size unchanged.
        cache.put("10.255.255.255", "newest.example");
        assert_eq!(cache.len(), DEFAULT_MAX_SIZE as u32);
        assert_eq!(cache.get("10.0.0.0"), None);
        assert_eq!(
            cache.get("10.255.255.255").as_deref(),
            Some("newest.example")
        );
    }
}

#[test]
fn unicode_domains_round_trip() {
    let cache = IpDomainCache::new(2);
    cache.put("2001:db8::1", "名字.example");
    assert_eq!(cache.get("2001:db8::1").as_deref(), Some("名字.example"));
}

//! The two-service state: plan/apply per service, cache isolation and the
//! "configuration changed -> rebuild" rule that `Configure` used to implement.

use super::*;
use crate::hash::hostname_to_hashes;

const NOW_MS: i64 = 1_000_000;

#[test]
fn invalid_host_yields_no_plan() {
    let engine = Engine::new(16, 60_000);
    for host in ["", "  ", ".", "a..b.com"] {
        assert!(
            engine.plan(SERVICE_SAFE_BROWSING, host, NOW_MS).is_none(),
            "host {host:?}"
        );
    }
}

#[test]
fn public_suffix_has_no_digest_to_check() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "com", NOW_MS)
        .expect("a public suffix is still a valid host");
    assert!(plan.empty);
    assert!(plan.found);
    assert!(!plan.blocked);
    assert!(plan.need_query.is_empty());
    assert_eq!(plan.question, SAFE_BROWSING_SUFFIX);
}

#[test]
fn fresh_host_asks_with_the_service_suffix() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_PARENTAL_CONTROL, "sub.host.com", NOW_MS)
        .expect("valid host");
    assert!(!plan.empty);
    assert!(!plan.found);
    assert_eq!(plan.need_query, hostname_to_hashes("sub.host.com"));
    assert!(plan.question.ends_with(PARENTAL_CONTROL_SUFFIX));
}

#[test]
fn applied_answer_is_cached_for_the_next_plan() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    let listed = plan.need_query[0];

    assert!(engine.apply(SERVICE_SAFE_BROWSING, &plan.need_query, &[listed], NOW_MS));
    assert_eq!(engine.cache_entries(SERVICE_SAFE_BROWSING), Some(1));

    let cached = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS + 1)
        .expect("valid host");
    assert!(cached.found);
    assert!(cached.blocked);
    assert!(cached.need_query.is_empty());
}

#[test]
fn unlisted_answer_is_cached_as_a_pass() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    assert!(!engine.apply(SERVICE_SAFE_BROWSING, &plan.need_query, &[], NOW_MS));

    let cached = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS + 1)
        .expect("valid host");
    assert!(cached.found);
    assert!(!cached.blocked);
}

#[test]
fn the_two_services_do_not_share_entries() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    engine.apply(
        SERVICE_SAFE_BROWSING,
        &plan.need_query,
        &plan.need_query,
        NOW_MS,
    );

    assert_eq!(engine.cache_entries(SERVICE_SAFE_BROWSING), Some(1));
    assert_eq!(engine.cache_entries(SERVICE_PARENTAL_CONTROL), Some(0));

    let parental = engine
        .plan(SERVICE_PARENTAL_CONTROL, "host.com", NOW_MS)
        .expect("valid host");
    assert!(!parental.found);
    assert!(!parental.need_query.is_empty());
}

#[test]
fn unknown_service_is_rejected() {
    let engine = Engine::new(16, 60_000);
    assert!(engine.plan(9, "host.com", NOW_MS).is_none());
    assert_eq!(engine.cache_entries(9), None);
    assert!(!engine.apply(9, &[[0u8; 32]], &[[0u8; 32]], NOW_MS));
}

#[test]
fn configure_keeps_the_caches_when_nothing_changed() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    engine.apply(SERVICE_SAFE_BROWSING, &plan.need_query, &[], NOW_MS);

    engine.configure(16, 60_000);
    assert_eq!(engine.cache_entries(SERVICE_SAFE_BROWSING), Some(1));
}

#[test]
fn configure_rebuilds_both_caches_when_the_ttl_changes() {
    let engine = Engine::new(16, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    engine.apply(SERVICE_SAFE_BROWSING, &plan.need_query, &[], NOW_MS);

    engine.configure(16, 120_000);
    assert_eq!(engine.cache_entries(SERVICE_SAFE_BROWSING), Some(0));
    assert_eq!(engine.cache_entries(SERVICE_PARENTAL_CONTROL), Some(0));
}

#[test]
fn a_zero_sized_configuration_rebuilds_every_time() {
    // The old `Configure` compared the live (defaulted) capacity against the raw configured size,
    // so `CacheSize = 0` rebuilt on every call. Kept as-is: clearing a cache is the only effect.
    let engine = Engine::new(0, 60_000);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    engine.apply(SERVICE_SAFE_BROWSING, &plan.need_query, &[], NOW_MS);
    assert_eq!(engine.cache_entries(SERVICE_SAFE_BROWSING), Some(1));

    engine.configure(0, 60_000);
    assert_eq!(engine.cache_entries(SERVICE_SAFE_BROWSING), Some(0));
}

#[test]
fn entries_expire_against_the_injected_clock() {
    let engine = Engine::new(16, 500);
    let plan = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS)
        .expect("valid host");
    engine.apply(SERVICE_SAFE_BROWSING, &plan.need_query, &[], NOW_MS);

    let live = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS + 500)
        .expect("valid host");
    assert!(live.found);

    let expired = engine
        .plan(SERVICE_SAFE_BROWSING, "host.com", NOW_MS + 501)
        .expect("valid host");
    assert!(!expired.found);
}

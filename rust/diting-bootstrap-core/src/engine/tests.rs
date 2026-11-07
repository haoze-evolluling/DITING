use super::*;
use crate::health::COOLDOWN_FAILURE_THRESHOLD;

const T0: i64 = 1_700_000_000_000_000_000;

fn entries(pairs: &[(&str, f64)]) -> Vec<(String, f64)> {
    pairs
        .iter()
        .map(|(id, weight)| ((*id).to_string(), *weight))
        .collect()
}

/// A roll that stays below every exploration rate, and one that never explores.
const NO_EXPLORE: f64 = 0.5;

#[test]
fn empty_and_single_configs_skip_the_scores() {
    let kernel = BootstrapKernel::new();
    assert_eq!(kernel.plan(&[], T0, 0.0, 0.0, 0), Plan::default());

    let one = entries(&[("only", 1.0)]);
    let plan = kernel.plan(&one, T0, 0.0, 0.0, 0);
    assert_eq!(plan.primary, Some(0));
    assert!(plan.fallbacks.is_empty());
    assert!(!plan.exploration);
    assert_eq!(kernel.health_count(), 0);
}

#[test]
fn weighted_draw_follows_the_configured_weights() {
    let kernel = BootstrapKernel::new();
    let list = entries(&[("slow", 1.0), ("fast", 3.0)]);

    // roll 0.5 * 4 = 2: after the first weight (1) there is 1 left, the second (3) crosses zero.
    let fast = kernel.plan(&list, T0, NO_EXPLORE, 0.5, 0);
    assert_eq!(fast.primary, Some(1));
    assert_eq!(fast.fallbacks, vec![0]);

    // roll 0.1 * 4 = 0.4 < 1, so the first endpoint wins.
    let slow = kernel.plan(&list, T0, NO_EXPLORE, 0.1, 0);
    assert_eq!(slow.primary, Some(0));
    assert_eq!(slow.fallbacks, vec![1]);
}

#[test]
fn exploration_uses_the_injected_index() {
    let kernel = BootstrapKernel::new();
    let list = entries(&[("a", 1.0), ("b", 1.0)]);

    // Cold sample counts keep the exploration rate at 8%, so 0.01 explores.
    let pick_second = kernel.plan(&list, T0, 0.01, 0.0, 3);
    assert!(pick_second.exploration);
    assert_eq!(pick_second.primary, Some(1));

    let pick_first = kernel.plan(&list, T0, 0.01, 0.0, 2);
    assert!(pick_first.exploration);
    assert_eq!(pick_first.primary, Some(0));
}

#[test]
fn cooling_endpoints_are_skipped_unless_every_endpoint_cools() {
    let kernel = BootstrapKernel::new();
    for _ in 0..COOLDOWN_FAILURE_THRESHOLD {
        kernel.record_result("bad", false, 100, T0);
    }
    let list = entries(&[("bad", 1.0), ("good", 1.0)]);

    let plan = kernel.plan(&list, T0, NO_EXPLORE, 0.0, 0);
    assert_eq!(plan.primary, Some(1));
    assert_eq!(plan.fallbacks, vec![0]);

    for _ in 0..COOLDOWN_FAILURE_THRESHOLD {
        kernel.record_result("good", false, 100, T0);
    }
    let all_cooling = kernel.plan(&list, T0, NO_EXPLORE, 0.0, 0);
    assert_eq!(all_cooling.primary, Some(0));
    assert_eq!(all_cooling.fallbacks, vec![1]);
}

#[test]
fn fallbacks_are_sorted_by_weight_descending_and_stable() {
    let kernel = BootstrapKernel::new();
    let list = entries(&[("a", 1.0), ("b", 3.0), ("c", 2.0)]);
    let plan = kernel.plan(&list, T0, NO_EXPLORE, 0.0, 0);
    assert_eq!(plan.primary, Some(0));
    assert_eq!(plan.fallbacks, vec![1, 2]);
}

#[test]
fn a_duplicate_id_never_appears_as_a_fallback() {
    let kernel = BootstrapKernel::new();
    let list = entries(&[("x", 1.0), ("x", 2.0), ("y", 0.5)]);
    let plan = kernel.plan(&list, T0, NO_EXPLORE, 0.0, 0);
    assert_eq!(plan.primary, Some(0));
    assert_eq!(plan.fallbacks, vec![2]);
}

#[test]
fn cache_entries_live_exactly_one_minute() {
    let kernel = BootstrapKernel::new();
    kernel.cache_put("example.com", "93.184.216.34", T0);
    assert_eq!(
        kernel.cache_get("example.com", T0),
        Some("93.184.216.34".to_string())
    );
    assert_eq!(
        kernel.cache_get("example.com", T0 + CACHE_TTL_NS),
        Some("93.184.216.34".to_string())
    );
    assert_eq!(kernel.cache_get("example.com", T0 + CACHE_TTL_NS + 1), None);
    assert_eq!(kernel.cache_get("missing.example", T0), None);
}

#[test]
fn config_change_clears_the_cache_but_keeps_health() {
    let kernel = BootstrapKernel::new();
    kernel.record_result("fast", true, 20, T0);
    kernel.cache_put("example.com", "1.2.3.4", T0);
    assert_eq!(kernel.health_count(), 1);

    kernel.clear_cache();
    assert_eq!(kernel.cache_get("example.com", T0), None);
    assert_eq!(kernel.health_count(), 1);

    kernel.reset();
    assert_eq!(kernel.health_count(), 0);
}

#[test]
fn score_reads_the_same_state_that_plan_uses() {
    let kernel = BootstrapKernel::new();
    for _ in 0..5 {
        kernel.record_result("fast", true, 10, T0);
    }
    let score = kernel.score("fast", 1.0, T0);
    assert!(score.weight > 1.0);
    assert_eq!(score.sample_count, 5.0);
}

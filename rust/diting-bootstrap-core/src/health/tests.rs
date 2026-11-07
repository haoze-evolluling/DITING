use super::*;

const T0: i64 = 1_700_000_000_000_000_000;

#[test]
fn cold_health_reports_the_configured_weight() {
    let mut health = Health::new(T0);
    let score = health.score(1.0, T0);
    assert_eq!(score.weight, 1.0);
    assert_eq!(score.sample_count, 0.0);
    assert!(!score.cooling_down);

    let mut custom = Health::new(T0);
    assert_eq!(custom.score(2.5, T0).weight, 2.5);
    let mut fallback = Health::new(T0);
    assert_eq!(fallback.score(0.0, T0).weight, 1.0);
    let mut negative = Health::new(T0);
    assert_eq!(negative.score(-3.0, T0).weight, 1.0);
}

#[test]
fn fast_successes_raise_the_weight_and_failures_arm_the_cooldown() {
    let mut health = Health::new(T0);
    for _ in 0..5 {
        health.record_result(true, 10, T0);
    }
    let fast = health.score(1.0, T0);
    assert!(fast.weight > 1.0, "weight {}", fast.weight);
    assert!(!fast.cooling_down);

    for _ in 0..3 {
        health.record_result(false, 3000, T0);
    }
    let failed = health.score(1.0, T0);
    assert!(failed.cooling_down);
    assert!(failed.weight < 0.5, "weight {}", failed.weight);
    assert_eq!(failed.sample_count, 8.0);
}

#[test]
fn cooldown_expires_at_the_strict_boundary() {
    let mut health = Health::new(T0);
    for _ in 0..COOLDOWN_FAILURE_THRESHOLD {
        health.record_result(false, 100, T0);
    }
    assert!(health.score(1.0, T0).cooling_down);
    assert!(
        health
            .score(1.0, T0 + COOLDOWN_DURATION_NS - 1)
            .cooling_down
    );
    // `now.Before(cooldownUntil)` is strict: at the deadline the endpoint is eligible again.
    assert!(!health.score(1.0, T0 + COOLDOWN_DURATION_NS).cooling_down);
}

#[test]
fn success_clears_the_cooldown_immediately() {
    let mut health = Health::new(T0);
    for _ in 0..COOLDOWN_FAILURE_THRESHOLD {
        health.record_result(false, 100, T0);
    }
    assert!(health.score(1.0, T0).cooling_down);
    health.record_result(true, 20, T0 + 1);
    assert!(!health.score(1.0, T0 + 1).cooling_down);
    assert!(health.snapshot().cooldown_until_ns == 0);
}

#[test]
fn decay_halves_the_sample_count_every_half_life() {
    let mut health = Health::new(T0);
    for _ in 0..10 {
        health.record_result(true, 30, T0);
    }
    assert_eq!(health.score(1.0, T0).sample_count, 10.0);
    let after = health.score(1.0, T0 + 1_800_000_000_000).sample_count;
    assert!((after - 5.0).abs() < 1e-9, "sample {after}");
    let after_two = health.score(1.0, T0 + 3_600_000_000_000).sample_count;
    assert!((after_two - 2.5).abs() < 1e-9, "sample {after_two}");
}

#[test]
fn elapsed_is_clamped_to_one_millisecond() {
    let mut negative = Health::new(T0);
    negative.record_result(true, -5, T0);
    let mut zero = Health::new(T0);
    zero.record_result(true, 0, T0);
    assert_eq!(negative.snapshot().ewma_ms, zero.snapshot().ewma_ms);
    assert_eq!(zero.snapshot().ewma_ms, 250.0 * 0.75 + 0.25);
}

#[test]
fn jitter_uses_the_new_ewma() {
    // 10 ms then 40 ms: ewma after the second sample is 190 * 0.75 + 40 * 0.25 = 152.5, and the
    // deviation is |40 - 152.5| = 112.5; the previous jitter (36) decays by 0.8, so
    // 36 * 0.8 + 112.5 * 0.2 = 51.3, matching the Go ordering.
    let mut health = Health::new(T0);
    health.record_result(true, 10, T0);
    health.record_result(true, 40, T0);
    let snapshot = health.snapshot();
    assert!((snapshot.ewma_ms - 152.5).abs() < 1e-9);
    assert!((snapshot.jitter_ms - 51.3).abs() < 1e-9);
}

#[test]
fn zero_last_update_is_stamped_without_decay() {
    let mut health = Health::new(0);
    health.record_result(false, 10, T0);
    // apply_decay sees a zero stamp, adopts `now`, and does not scale the counters.
    assert_eq!(health.snapshot().decayed_failures, 1.0);
    assert_eq!(health.snapshot().last_updated_ns, T0);
}

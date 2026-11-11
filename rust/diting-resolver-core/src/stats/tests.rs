//! Unit tests of the model itself. The trace in `tests/corpus.rs` pins every value against the
//! original Go implementation; these cover the branches the trace does not reach (clamps, the
//! weight floor, the cooldown cap) and document the intended shape of the estimator.

use super::*;

const MS: i64 = 1_000_000;
const S: i64 = 1_000_000_000;

#[test]
fn cold_provider_reports_the_documented_defaults() {
    let stats = ProviderStats::new();
    let snapshot = stats.snapshot();
    assert_eq!(snapshot.ewma_rtt_ns, DEFAULT_EWMA_NS);
    assert_eq!(snapshot.rtt_var_ns, 0);
    assert_eq!(snapshot.fail_rate, 0.0);
    assert_eq!(snapshot.sample_count, 0);
    assert_eq!(snapshot.failure_count, 0);
    assert_eq!(snapshot.circuit_open_until_ns, 0);
    assert!(!snapshot.probe_in_flight);
    assert_eq!(stats.score(0), DEFAULT_EWMA_NS);
    assert_eq!(stats.hedge_delay(), HEDGE_DELAY_COLD_NS);
    assert_eq!(stats.attempt_timeout(), ATTEMPT_TIMEOUT_COLD_NS);
    assert_eq!(stats.udp_retry_delay(), UDP_RETRY_DELAY_COLD_NS);
    assert!(stats.allow_attempt(0));
}

#[test]
fn tail_latency_estimators_clamp_both_ends() {
    let stats = ProviderStats::new();
    // One slow sample: SRTT 2 s, RTTVAR 1 s, so all three estimates exceed their upper clamp.
    stats.record_success(2 * S, 0);
    assert_eq!(stats.hedge_delay(), HEDGE_DELAY_MAX_NS);
    assert_eq!(stats.attempt_timeout(), ATTEMPT_TIMEOUT_MAX_NS);
    assert_eq!(stats.udp_retry_delay(), UDP_RETRY_DELAY_MAX_NS);

    // Fast, stable samples pull all three under their lower clamp. RTTVAR decays by 0.75 per
    // sample, so it needs ~50 samples before the variance term stops dominating.
    for _ in 0..50 {
        stats.record_success(2 * MS, 0);
    }
    assert_eq!(stats.hedge_delay(), HEDGE_DELAY_MIN_NS);
    assert_eq!(stats.attempt_timeout(), ATTEMPT_TIMEOUT_MIN_NS);
    assert_eq!(stats.udp_retry_delay(), UDP_RETRY_DELAY_MIN_NS);
}

#[test]
fn circuit_opens_at_the_third_failure_and_admits_one_probe() {
    let stats = ProviderStats::new();
    let now = 1_000 * S;
    stats.record_failure(now);
    stats.record_failure(now);
    assert_eq!(stats.snapshot().circuit_open_until_ns, 0);
    assert!(stats.allow_attempt(now), "a closed circuit always allows");

    stats.record_failure(now);
    assert_eq!(stats.failure_count(), CIRCUIT_TRIP_THRESHOLD);
    assert_eq!(
        stats.snapshot().circuit_open_until_ns,
        now + CIRCUIT_BASE_COOLDOWN_NS
    );
    assert!(!stats.allow_attempt(now));
    assert!(!stats.allow_attempt(now + CIRCUIT_BASE_COOLDOWN_NS - 1));
    assert!(stats.allow_attempt(now + CIRCUIT_BASE_COOLDOWN_NS));
    assert!(
        !stats.allow_attempt(now + CIRCUIT_BASE_COOLDOWN_NS),
        "the half-open probe must stay single"
    );

    stats.record_success(5 * MS, now + CIRCUIT_BASE_COOLDOWN_NS + 1);
    assert_eq!(stats.failure_count(), 0);
    assert_eq!(stats.snapshot().circuit_open_until_ns, 0);
    assert!(stats.allow_attempt(now + CIRCUIT_BASE_COOLDOWN_NS + 2));
}

#[test]
fn cooldown_doubles_and_caps_at_one_minute() {
    let stats = ProviderStats::new();
    let now = 1_000 * S;
    for count in 1..=12u32 {
        stats.record_failure(now);
        assert_eq!(stats.failure_count(), count);
        if count < CIRCUIT_TRIP_THRESHOLD {
            assert_eq!(stats.snapshot().circuit_open_until_ns, 0);
            continue;
        }
        let shift = (count - CIRCUIT_TRIP_THRESHOLD).min(CIRCUIT_MAX_SHIFT);
        let expected = (CIRCUIT_BASE_COOLDOWN_NS << shift).min(CIRCUIT_MAX_COOLDOWN_NS);
        assert_eq!(
            stats.snapshot().circuit_open_until_ns,
            now + expected,
            "after {count} failures"
        );
    }
}

#[test]
fn policy_failure_trips_immediately_and_zero_weight_counts_once() {
    let stats = ProviderStats::new();
    stats.record_failure_weight(0, 0);
    assert_eq!(stats.failure_count(), 1, "the weight floor is one");

    let stats = ProviderStats::new();
    stats.record_policy_failure(0);
    assert_eq!(stats.failure_count(), CIRCUIT_TRIP_THRESHOLD);
    assert!(!stats.allow_attempt(0));
}

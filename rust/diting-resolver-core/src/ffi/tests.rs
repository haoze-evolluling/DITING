//! Boundary tests: the ABI number, the null-handle behaviour and a full round trip through the
//! exported symbols (the Go loader calls exactly these).

use super::*;
use crate::stats::{
    ATTEMPT_TIMEOUT_COLD_NS, DEFAULT_EWMA_NS, HEDGE_DELAY_COLD_NS, UDP_RETRY_DELAY_COLD_NS,
};

const MS: i64 = 1_000_000;

#[test]
fn abi_version_is_the_one_the_loader_validates() {
    assert_eq!(diting_resolver_abi_version(), ABI_VERSION);
    assert_eq!(ABI_VERSION, 1);
}

#[test]
fn a_null_handle_is_a_no_op_with_cold_answers() {
    let null: *const ProviderStats = std::ptr::null();
    unsafe {
        assert_eq!(diting_resolver_record_success(null, MS, 0), 0);
        assert_eq!(diting_resolver_record_failure(null, 1, 0), 0);
        assert_eq!(diting_resolver_record_policy_failure(null, 0), 0);
        assert_eq!(diting_resolver_record_censored(null, MS), 0);
        assert_eq!(diting_resolver_allow_attempt(null, 0), 1);
        assert_eq!(diting_resolver_score(null, 0), DEFAULT_EWMA_NS);
        assert_eq!(diting_resolver_hedge_delay(null), HEDGE_DELAY_COLD_NS);
        assert_eq!(
            diting_resolver_attempt_timeout(null),
            ATTEMPT_TIMEOUT_COLD_NS
        );
        assert_eq!(
            diting_resolver_udp_retry_delay(null),
            UDP_RETRY_DELAY_COLD_NS
        );
        assert_eq!(diting_resolver_sample_count(null), 0);
        assert_eq!(diting_resolver_failure_count(null), 0);
        diting_resolver_free(std::ptr::null_mut());
    }
}

#[test]
fn handle_round_trip_through_the_exported_symbols() {
    let handle = diting_resolver_new();
    assert!(!handle.is_null());
    unsafe {
        assert_eq!(diting_resolver_sample_count(handle), 0);
        assert_eq!(diting_resolver_failure_count(handle), 0);

        assert_eq!(diting_resolver_record_success(handle, 20 * MS, 1_000), 1);
        assert_eq!(diting_resolver_sample_count(handle), 1);
        assert_eq!(diting_resolver_score(handle, 1_000), 20 * MS);
        // SRTT 20 ms + 2*RTTVAR 10 ms: above the 20 ms floor.
        assert_eq!(diting_resolver_hedge_delay(handle), 40 * MS);

        assert_eq!(diting_resolver_record_failure(handle, 1, 2_000), 1);
        assert_eq!(diting_resolver_failure_count(handle), 1);
        assert_eq!(diting_resolver_record_policy_failure(handle, 3_000), 1);
        assert_eq!(diting_resolver_failure_count(handle), 4);
        assert_eq!(diting_resolver_allow_attempt(handle, 3_000), 0);

        assert_eq!(diting_resolver_record_censored(handle, 50 * MS), 1);
        assert_eq!(diting_resolver_record_success(handle, 5 * MS, 4_000), 1);
        assert_eq!(diting_resolver_failure_count(handle), 0);
        assert_eq!(diting_resolver_sample_count(handle), 3);
        assert_eq!(diting_resolver_allow_attempt(handle, 4_000), 1);

        diting_resolver_free(handle);
    }
}

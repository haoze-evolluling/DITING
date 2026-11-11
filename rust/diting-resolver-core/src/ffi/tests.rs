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
    assert_eq!(ABI_VERSION, 2);
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

/// The session payload of one `smart_prediction` query with two providers.
fn session_payload() -> Vec<u8> {
    let mut out = vec![crate::payload::LAYOUT_VERSION, 3];
    out.extend_from_slice(&2u32.to_le_bytes());
    for (id, encrypted, score) in [("plain", 0u8, 10 * MS), ("doh", 1u8, 20 * MS)] {
        out.extend_from_slice(&(id.len() as u32).to_le_bytes());
        out.extend_from_slice(id.as_bytes());
        out.push(encrypted);
        out.push(1);
        out.extend_from_slice(&score.to_le_bytes());
        out.extend_from_slice(&(50 * MS).to_le_bytes());
        out.extend_from_slice(&(1_500 * MS).to_le_bytes());
    }
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&(5_000 * MS).to_le_bytes());
    out.extend_from_slice(&(25 * MS).to_le_bytes());
    out
}

unsafe fn take(out_pointer: *mut u8, out_length: usize) -> Vec<u8> {
    let payload = std::slice::from_raw_parts(out_pointer, out_length).to_vec();
    diting_resolver_free_bytes(out_pointer, out_length);
    payload
}

#[test]
fn a_session_rejects_a_drifted_payload() {
    unsafe {
        assert!(diting_resolver_sched_new(std::ptr::null(), 0).is_null());
        let mut payload = session_payload();
        payload[0] = crate::payload::LAYOUT_VERSION + 1;
        assert!(diting_resolver_sched_new(payload.as_ptr(), payload.len()).is_null());
    }
}

#[test]
fn a_session_answers_start_and_result_with_steps() {
    let payload = session_payload();
    let handle = unsafe { diting_resolver_sched_new(payload.as_ptr(), payload.len()) };
    assert!(!handle.is_null());
    unsafe {
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut length: usize = 0;
        assert_eq!(
            diting_resolver_sched_start(handle, &mut out, &mut length),
            STATUS_OK
        );
        let step = take(out, length);
        assert_eq!(step[0], crate::payload::LAYOUT_VERSION);
        // One launch request: the ranked plain provider (index 0).
        assert_eq!(u32::from_le_bytes(step[19..23].try_into().unwrap()), 1);
        assert_eq!(u32::from_le_bytes(step[23..27].try_into().unwrap()), 0);

        let mut out: *mut u8 = std::ptr::null_mut();
        let mut length: usize = 0;
        assert_eq!(
            diting_resolver_sched_launched(handle, 0, 1, &mut out, &mut length),
            STATUS_OK
        );
        let step = take(out, length);
        // The hedge is armed with the launched provider's delay and nothing is terminal.
        assert_eq!(step[1], 1);
        assert_eq!(i64::from_le_bytes(step[2..10].try_into().unwrap()), 50 * MS);
        assert_eq!(step[19], 0); // no launch request
        assert_eq!(step[23], 0); // not terminal

        let message = b"servfail";
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut length: usize = 0;
        assert_eq!(
            diting_resolver_sched_result(
                handle,
                0,
                0,
                5 * MS,
                6 * MS,
                0,
                message.as_ptr(),
                message.len(),
                &mut out,
                &mut length,
            ),
            STATUS_OK
        );
        let step = take(out, length);
        // The failure advances immediately to the next candidate.
        assert_eq!(u32::from_le_bytes(step[19..23].try_into().unwrap()), 1);
        assert_eq!(u32::from_le_bytes(step[23..27].try_into().unwrap()), 1);

        diting_resolver_sched_free(handle);
    }
}

#[test]
fn session_calls_without_a_handle_are_rejected() {
    unsafe {
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut length: usize = 0;
        let null: *const Schedule = std::ptr::null();
        assert_eq!(
            diting_resolver_sched_start(null, &mut out, &mut length),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_resolver_sched_launched(null, 0, 1, &mut out, &mut length),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_resolver_sched_result(
                null,
                0,
                1,
                0,
                0,
                0,
                std::ptr::null(),
                0,
                &mut out,
                &mut length
            ),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_resolver_sched_hedge(null, &mut out, &mut length),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_resolver_sched_grace(null, 0, &mut out, &mut length),
            STATUS_BAD_ARGUMENT
        );
        diting_resolver_sched_free(std::ptr::null_mut());
        diting_resolver_free_bytes(std::ptr::null_mut(), 0);
    }
}

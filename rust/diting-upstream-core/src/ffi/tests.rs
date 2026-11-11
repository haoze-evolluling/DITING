use std::ptr;

use super::*;
use crate::payload::{decode_address, decode_ids, decode_target, decode_tuning};

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_upstream_abi_version(), 1);
}

#[test]
fn the_tuning_table_goes_through_the_abi() {
    let mut out: *mut u8 = ptr::null_mut();
    let mut out_len = 0usize;
    unsafe {
        assert_eq!(diting_upstream_tuning(&mut out, &mut out_len), STATUS_OK);
        let payload = std::slice::from_raw_parts(out, out_len);
        assert_eq!(decode_tuning(payload), Some(TUNING));
        diting_upstream_free_bytes(out, out_len);
    }
}

#[test]
fn targets_and_dial_addresses_go_through_the_abi() {
    let mut out: *mut u8 = ptr::null_mut();
    let mut out_len = 0usize;
    let server = b"dns.google";
    unsafe {
        assert_eq!(
            diting_upstream_target(
                PROTOCOL_DOT,
                server.as_ptr(),
                server.len(),
                &mut out,
                &mut out_len
            ),
            STATUS_OK
        );
        let payload = std::slice::from_raw_parts(out, out_len);
        assert_eq!(
            decode_target(payload),
            Some(("dns.google".to_string(), "853".to_string()))
        );
        diting_upstream_free_bytes(out, out_len);

        assert_eq!(
            diting_upstream_target(9, server.as_ptr(), server.len(), &mut out, &mut out_len),
            STATUS_BAD_ARGUMENT
        );

        let host = b"dns.google";
        let port = b"853";
        let bootstrapped = b"1.2.3.4";
        assert_eq!(
            diting_upstream_dial_address(
                host.as_ptr(),
                host.len(),
                port.as_ptr(),
                port.len(),
                bootstrapped.as_ptr(),
                bootstrapped.len(),
                &mut out,
                &mut out_len
            ),
            STATUS_OK
        );
        let payload = std::slice::from_raw_parts(out, out_len);
        assert_eq!(decode_address(payload), Some("1.2.3.4:853".to_string()));
        diting_upstream_free_bytes(out, out_len);
    }
}

#[test]
fn framing_and_length_rules_go_through_the_abi() {
    let query = [0xAAu8, 0xBB];
    let mut frame = [0u8; 4];
    unsafe {
        assert_eq!(
            diting_upstream_frame(query.as_ptr(), query.len(), frame.as_mut_ptr(), frame.len()),
            4
        );
        assert_eq!(frame, [0, 2, 0xAA, 0xBB]);
        assert_eq!(
            diting_upstream_frame(query.as_ptr(), query.len(), frame.as_mut_ptr(), 3),
            RESULT_TOO_SMALL
        );

        assert_eq!(diting_upstream_tcp_response_length(frame.as_ptr(), 2), 2);
        assert_eq!(diting_upstream_tcp_response_length(frame.as_ptr(), 1), -1);

        let mut length = 0u32;
        assert_eq!(
            diting_upstream_dot_response_length(frame.as_ptr(), 2, &mut length),
            STATUS_OK
        );
        assert_eq!(length, 2);
        let zero = [0u8, 0u8];
        assert_eq!(
            diting_upstream_dot_response_length(zero.as_ptr(), 2, &mut length),
            1
        );
        assert_eq!(length, 0);

        let mut raw = [0u8; 12];
        assert_eq!(diting_upstream_is_truncated(raw.as_ptr(), raw.len()), 0);
        raw[2] = 0x02;
        assert_eq!(diting_upstream_is_truncated(raw.as_ptr(), raw.len()), 1);
        assert_eq!(diting_upstream_is_truncated(ptr::null(), 0), 0);

        let doq = [0u8, 2, 0xAA, 0xBB];
        assert_eq!(diting_upstream_doq_skip(doq.as_ptr(), doq.len()), 2);
        let not_doq = [0u8, 5, 0xAA, 0xBB];
        assert_eq!(diting_upstream_doq_skip(not_doq.as_ptr(), not_doq.len()), 0);
    }
}

#[test]
fn the_plain_retry_arithmetic_goes_through_the_abi() {
    unsafe {
        assert_eq!(
            diting_upstream_plain_initial_delay_ns(0),
            TUNING.plain_retry_default_ns
        );
        assert_eq!(
            diting_upstream_plain_first_deadline_ns(1000, 400, 5000),
            1400
        );
        let mut deadline = 0i64;
        assert_eq!(
            diting_upstream_plain_retry_deadline_ns(1400, 400, 5000, 0, &mut deadline),
            1
        );
        assert_eq!(deadline, 2200);
        assert_eq!(
            diting_upstream_plain_retry_deadline_ns(5000, 400, 5000, 0, &mut deadline),
            0
        );
    }
}

#[test]
fn doh_classification_and_strategy_go_through_the_abi() {
    let error = b"Post: EOF";
    unsafe {
        assert_eq!(diting_upstream_doh_status_kind(200), 0);
        assert_eq!(diting_upstream_doh_status_kind(403), 1);
        assert_eq!(diting_upstream_doh_status_kind(500), 2);
        assert_eq!(
            diting_upstream_doh_should_retry(1, error.as_ptr(), error.len()),
            1
        );
        assert_eq!(
            diting_upstream_doh_should_retry(2, error.as_ptr(), error.len()),
            0
        );

        let mode = b"race";
        assert_eq!(diting_upstream_strategy(mode.as_ptr(), mode.len()), 2);
        assert_eq!(diting_upstream_strategy(ptr::null(), 0), 0);
        assert_eq!(diting_upstream_is_policy_rejection(5), 1);
        assert_eq!(diting_upstream_is_policy_rejection(2), 0);
    }
}

#[test]
fn the_pool_goes_through_the_abi() {
    let host = b"dns:853";
    let pool = diting_upstream_pool_new();
    assert!(!pool.is_null());
    let mut id = 0u64;
    unsafe {
        assert_eq!(
            diting_upstream_pool_acquire(pool, host.as_ptr(), host.len(), 0, &mut id),
            ACQUIRE_EMPTY
        );
        assert_eq!(
            diting_upstream_pool_release(pool, host.as_ptr(), host.len(), 11, 0),
            1
        );
        assert_eq!(diting_upstream_pool_len(pool, host.as_ptr(), host.len()), 1);
        assert_eq!(
            diting_upstream_pool_acquire(pool, host.as_ptr(), host.len(), 10, &mut id),
            ACQUIRE_IDLE
        );
        assert_eq!(id, 11);

        assert_eq!(
            diting_upstream_pool_release(pool, host.as_ptr(), host.len(), 11, 0),
            1
        );
        assert_eq!(
            diting_upstream_pool_acquire(pool, host.as_ptr(), host.len(), 20_000, &mut id),
            ACQUIRE_EXPIRED
        );
        assert_eq!(id, 11);

        assert_eq!(
            diting_upstream_pool_release(pool, host.as_ptr(), host.len(), 12, 0),
            1
        );
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len = 0usize;
        assert_eq!(
            diting_upstream_pool_close_all(pool, &mut out, &mut out_len),
            STATUS_OK
        );
        let payload = std::slice::from_raw_parts(out, out_len);
        assert_eq!(decode_ids(payload), Some(vec![12]));
        diting_upstream_free_bytes(out, out_len);
        diting_upstream_pool_free(pool);
    }
}

#[test]
fn a_null_pool_is_an_empty_pool() {
    let host = b"dns:853";
    let mut id = 0u64;
    unsafe {
        assert_eq!(
            diting_upstream_pool_acquire(ptr::null(), host.as_ptr(), host.len(), 0, &mut id),
            ACQUIRE_EMPTY
        );
        assert_eq!(
            diting_upstream_pool_release(ptr::null(), host.as_ptr(), host.len(), 1, 0),
            0
        );
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len = 0usize;
        assert_eq!(
            diting_upstream_pool_close_all(ptr::null(), &mut out, &mut out_len),
            STATUS_OK
        );
        let payload = std::slice::from_raw_parts(out, out_len);
        assert_eq!(decode_ids(payload), Some(Vec::new()));
        diting_upstream_free_bytes(out, out_len);
        diting_upstream_pool_free(ptr::null_mut());
        diting_upstream_free_bytes(ptr::null_mut(), 0);
    }
}

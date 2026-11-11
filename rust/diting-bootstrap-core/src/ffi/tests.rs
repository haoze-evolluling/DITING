use super::*;
use crate::engine::CACHE_TTL_NS;
use crate::payload::{encode_plan_entries, LAYOUT_VERSION, SCORE_BYTES};

const T0: i64 = 1_700_000_000_000_000_000;

fn decode_plan(bytes: &[u8]) -> (i32, bool, Vec<u32>) {
    assert_eq!(bytes[0], LAYOUT_VERSION);
    let primary = i32::from_le_bytes(bytes[1..5].try_into().unwrap());
    let exploration = bytes[5] != 0;
    let count = u32::from_le_bytes(bytes[6..10].try_into().unwrap()) as usize;
    let mut fallbacks = Vec::with_capacity(count);
    let mut position = 10;
    for _ in 0..count {
        fallbacks.push(u32::from_le_bytes(
            bytes[position..position + 4].try_into().unwrap(),
        ));
        position += 4;
    }
    assert_eq!(position, bytes.len());
    (primary, exploration, fallbacks)
}

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_bootstrap_abi_version(), 1);
}

#[test]
fn a_null_handle_is_a_no_op() {
    assert_eq!(
        unsafe { diting_bootstrap_reset(ptr::null()) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_bootstrap_clear_cache(ptr::null()) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_bootstrap_record_result(ptr::null(), b"id".as_ptr(), 2, 1, 10, T0,) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(unsafe { diting_bootstrap_health_count(ptr::null()) }, 0);
    let mut out = [0u8; SCORE_BYTES];
    assert_eq!(
        unsafe {
            diting_bootstrap_score(
                ptr::null(),
                b"id".as_ptr(),
                2,
                1.0,
                T0,
                out.as_mut_ptr(),
                out.len(),
            )
        },
        RESULT_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe {
            diting_bootstrap_cache_get(
                ptr::null(),
                b"host".as_ptr(),
                4,
                T0,
                out.as_mut_ptr(),
                out.len(),
            )
        },
        RESULT_BAD_ARGUMENT
    );
    unsafe { diting_bootstrap_free(ptr::null_mut()) };
}

#[test]
fn plan_and_score_go_through_the_abi() {
    let kernel = diting_bootstrap_new();
    assert!(!kernel.is_null());
    let list = vec![("slow".to_string(), 1.0), ("fast".to_string(), 3.0)];
    let entries = encode_plan_entries(&list);
    let mut out = vec![0u8; 64];

    let written = unsafe {
        diting_bootstrap_plan(
            kernel,
            T0,
            0.5,
            0.5,
            0,
            entries.as_ptr(),
            entries.len(),
            out.as_mut_ptr(),
            out.len(),
        )
    };
    assert!(written > 0);
    let (primary, exploration, fallbacks) = decode_plan(&out[..written as usize]);
    assert_eq!(primary, 1);
    assert!(!exploration);
    assert_eq!(fallbacks, vec![0]);

    let mut score = [0u8; SCORE_BYTES];
    let length = unsafe {
        diting_bootstrap_score(
            kernel,
            b"fast".as_ptr(),
            4,
            3.0,
            T0,
            score.as_mut_ptr(),
            score.len(),
        )
    };
    assert_eq!(length, SCORE_BYTES as isize);
    assert_eq!(f64::from_le_bytes(score[..8].try_into().unwrap()), 3.0);
    assert_eq!(score[8], 0);
    assert_eq!(f64::from_le_bytes(score[9..].try_into().unwrap()), 0.0);

    assert_eq!(
        unsafe { diting_bootstrap_record_result(kernel, b"fast".as_ptr(), 4, 1, 10, T0) },
        STATUS_OK
    );
    assert_eq!(unsafe { diting_bootstrap_health_count(kernel) }, 2);

    unsafe { diting_bootstrap_free(kernel) };
}

#[test]
fn a_bad_entries_payload_is_reported() {
    let kernel = diting_bootstrap_new();
    let mut out = vec![0u8; 64];
    let garbage = [LAYOUT_VERSION, 1, 0, 0, 0];
    let result = unsafe {
        diting_bootstrap_plan(
            kernel,
            T0,
            0.0,
            0.0,
            0,
            garbage.as_ptr(),
            garbage.len(),
            out.as_mut_ptr(),
            out.len(),
        )
    };
    assert_eq!(result, RESULT_BAD_PAYLOAD);
    unsafe { diting_bootstrap_free(kernel) };
}

#[test]
fn a_small_buffer_is_reported() {
    let kernel = diting_bootstrap_new();
    let list = vec![("a".to_string(), 1.0), ("b".to_string(), 1.0)];
    let entries = encode_plan_entries(&list);
    let mut out = vec![0u8; 4];
    let result = unsafe {
        diting_bootstrap_plan(
            kernel,
            T0,
            0.0,
            0.0,
            0,
            entries.as_ptr(),
            entries.len(),
            out.as_mut_ptr(),
            out.len(),
        )
    };
    assert_eq!(result, RESULT_TOO_SMALL);
    unsafe { diting_bootstrap_free(kernel) };
}

#[test]
fn cache_get_and_put_round_trip_through_the_abi() {
    let kernel = diting_bootstrap_new();
    assert_eq!(
        unsafe {
            diting_bootstrap_cache_put(
                kernel,
                b"example.com".as_ptr(),
                11,
                b"93.184.216.34".as_ptr(),
                13,
                T0,
            )
        },
        STATUS_OK
    );

    let mut out = [0u8; 64];
    let length = unsafe {
        diting_bootstrap_cache_get(
            kernel,
            b"example.com".as_ptr(),
            11,
            T0,
            out.as_mut_ptr(),
            out.len(),
        )
    };
    assert_eq!(length, 13);
    assert_eq!(&out[..13], b"93.184.216.34");

    let expired = unsafe {
        diting_bootstrap_cache_get(
            kernel,
            b"example.com".as_ptr(),
            11,
            T0 + CACHE_TTL_NS + 1,
            out.as_mut_ptr(),
            out.len(),
        )
    };
    assert_eq!(expired, RESULT_BAD_ARGUMENT);

    unsafe { diting_bootstrap_free(kernel) };
}

#[test]
fn an_omitted_id_is_the_empty_health_key() {
    // A JSON config may leave `id` empty; the old Go health map keyed those under "". A null
    // pointer with length 0 must therefore be accepted, not rejected as a bad argument.
    let kernel = diting_bootstrap_new();
    assert_eq!(
        unsafe { diting_bootstrap_record_result(kernel, ptr::null(), 0, 1, 10, T0) },
        STATUS_OK
    );
    assert_eq!(unsafe { diting_bootstrap_health_count(kernel) }, 1);

    let mut score = [0u8; SCORE_BYTES];
    let length = unsafe {
        diting_bootstrap_score(
            kernel,
            ptr::null(),
            0,
            1.0,
            T0,
            score.as_mut_ptr(),
            score.len(),
        )
    };
    assert_eq!(length, SCORE_BYTES as isize);
    assert_eq!(f64::from_le_bytes(score[9..].try_into().unwrap()), 1.0);
    unsafe { diting_bootstrap_free(kernel) };
}

#[test]
fn invalid_utf8_is_rejected_not_truncated() {
    let kernel = diting_bootstrap_new();
    let invalid = [0xffu8, 0xfe];
    assert_eq!(
        unsafe {
            diting_bootstrap_record_result(kernel, invalid.as_ptr(), invalid.len(), 1, 10, T0)
        },
        STATUS_BAD_PAYLOAD
    );
    unsafe { diting_bootstrap_free(kernel) };
}

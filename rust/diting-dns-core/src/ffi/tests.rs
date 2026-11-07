//! Boundary tests: the ABI number, the null-handle behaviour and a full round trip through the
//! exported symbols (the Go loader calls exactly these).

use std::slice;

use super::*;
use crate::block::{RESPONSE_NO_DATA, RESPONSE_REFUSED};
use crate::payload::{decode_answer_response, LAYOUT_VERSION};

fn request(records: &[(u8, &[u8])]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(records.len() as u32).to_le_bytes());
    for (rrtype, address) in records {
        out.push(*rrtype);
        out.extend_from_slice(&(address.len() as u16).to_le_bytes());
        out.extend_from_slice(address);
    }
    out
}

#[test]
fn abi_version_is_the_one_the_loader_validates() {
    assert_eq!(diting_dns_abi_version(), ABI_VERSION);
    assert_eq!(ABI_VERSION, 1);
}

#[test]
fn inspect_answer_round_trips_through_the_exported_symbol() {
    let payload = request(&[(1, &[0, 0, 0, 0]), (28, &[0u8; 16])]);
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_dns_inspect_answer(payload.as_ptr(), payload.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);
    assert!(!out.is_null());
    let response = unsafe { slice::from_raw_parts(out, out_len) };
    assert_eq!(
        decode_answer_response(response),
        Some((true, "0.0.0.0,::".to_string()))
    );
    unsafe { diting_dns_free_bytes(out, out_len) };
}

#[test]
fn inspect_answer_rejects_bad_arguments_and_bad_payloads() {
    let payload = request(&[(1, &[1, 2, 3, 4])]);
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;

    unsafe {
        assert_eq!(
            diting_dns_inspect_answer(std::ptr::null(), 0, &mut out, &mut out_len),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_dns_inspect_answer(
                payload.as_ptr(),
                payload.len(),
                std::ptr::null_mut(),
                &mut out_len
            ),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_dns_inspect_answer(
                payload.as_ptr(),
                payload.len(),
                &mut out,
                std::ptr::null_mut()
            ),
            STATUS_BAD_ARGUMENT
        );

        let mut broken = payload.clone();
        broken[0] = LAYOUT_VERSION + 1;
        assert_eq!(
            diting_dns_inspect_answer(broken.as_ptr(), broken.len(), &mut out, &mut out_len),
            STATUS_BAD_PAYLOAD
        );
        assert!(out.is_null(), "a rejected request writes no payload");
        assert_eq!(out_len, 0);
    }
}

#[test]
fn dynamic_blocks_handle_round_trip() {
    let handle = diting_dns_blocks_new();
    assert!(!handle.is_null());
    let domain = b"chatty.example";
    unsafe {
        assert_eq!(
            diting_dns_blocks_response(
                handle,
                domain.as_ptr(),
                domain.len(),
                1,
                1,
                60_000_000_000,
                30_000_000_000,
                RESPONSE_REFUSED,
                0
            ),
            RESPONSE_NO_DATA
        );
        assert_eq!(
            diting_dns_blocks_response(
                handle,
                domain.as_ptr(),
                domain.len(),
                1,
                1,
                60_000_000_000,
                30_000_000_000,
                RESPONSE_REFUSED,
                1
            ),
            1,
            "the second request crosses the threshold"
        );

        diting_dns_blocks_reset(handle);
        assert_eq!(
            diting_dns_blocks_response(
                handle,
                domain.as_ptr(),
                domain.len(),
                1,
                1,
                60_000_000_000,
                30_000_000_000,
                RESPONSE_REFUSED,
                2
            ),
            RESPONSE_NO_DATA,
            "reset forgot the counter"
        );

        // Disabled echoes the fallback and records nothing.
        assert_eq!(
            diting_dns_blocks_response(
                handle,
                domain.as_ptr(),
                domain.len(),
                0,
                1,
                60_000_000_000,
                30_000_000_000,
                RESPONSE_REFUSED,
                3
            ),
            RESPONSE_REFUSED
        );

        diting_dns_blocks_free(handle);
    }
}

#[test]
fn a_null_tracker_echoes_the_fallback() {
    let domain = b"chatty.example";
    let response = unsafe {
        diting_dns_blocks_response(
            std::ptr::null(),
            domain.as_ptr(),
            domain.len(),
            1,
            1,
            60_000_000_000,
            30_000_000_000,
            RESPONSE_REFUSED,
            0,
        )
    };
    assert_eq!(response, RESPONSE_REFUSED);

    let handle = diting_dns_blocks_new();
    unsafe {
        // A non-UTF-8 domain is "not a hostname": the fallback mode, no state recorded.
        let invalid = b"\xff\xfe.example";
        assert_eq!(
            diting_dns_blocks_response(
                handle,
                invalid.as_ptr(),
                invalid.len(),
                1,
                1,
                60_000_000_000,
                30_000_000_000,
                RESPONSE_REFUSED,
                0,
            ),
            RESPONSE_REFUSED
        );
        diting_dns_blocks_free(handle);
        diting_dns_blocks_free(std::ptr::null_mut());
    }
}

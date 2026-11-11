//! Boundary tests: the ABI number, the null-handle behaviour and a full round trip through the
//! exported symbols (the Go loader calls exactly these).

use std::slice;

use super::*;
use crate::block::{RESPONSE_NO_DATA, RESPONSE_REFUSED};
use crate::payload::{
    decode_extracted, decode_lookup, decode_query_info, decode_reply, decode_validation,
    encode_rewrite_entries,
};

fn call_payload(
    function: unsafe extern "C" fn(*const u8, usize, *mut *mut u8, *mut usize) -> u32,
    input: &[u8],
) -> (u32, Vec<u8>) {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe { function(input.as_ptr(), input.len(), &mut out, &mut out_len) };
    if status != STATUS_OK {
        assert!(out.is_null());
        return (status, Vec::new());
    }
    assert!(!out.is_null());
    let payload = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
    unsafe { diting_dns_free_bytes(out, out_len) };
    (status, payload)
}

fn query(name: &str) -> Vec<u8> {
    let mut out = vec![0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0];
    for label in name.trim_end_matches('.').split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out.extend_from_slice(&[0, 1, 0, 1]);
    out
}

fn answer(query: &[u8], address: [u8; 4]) -> Vec<u8> {
    let mut out = query.to_vec();
    out[2] = 0x81;
    out[3] = 0x80;
    out[7] = 1;
    out.extend_from_slice(&[0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4]);
    out.extend_from_slice(&address);
    out
}

#[test]
fn abi_version_is_the_one_the_loader_validates() {
    assert_eq!(diting_dns_abi_version(), ABI_VERSION);
    assert_eq!(ABI_VERSION, 3);
}

#[test]
fn query_info_round_trips_through_the_exported_symbol() {
    let raw = query("Example.COM.");
    let (status, payload) = call_payload(diting_dns_query_info, &raw);
    assert_eq!(status, STATUS_OK);
    assert_eq!(
        decode_query_info(&payload),
        Some((true, "example.com".to_string(), 1))
    );
    let (status, payload) = call_payload(diting_dns_query_info, &[0u8; 8]);
    assert_eq!(status, STATUS_OK);
    assert_eq!(decode_query_info(&payload), Some((false, String::new(), 1)));
}

#[test]
fn validate_and_extract_round_trip_through_the_exported_symbols() {
    let raw_query = query("example.com.");
    let raw_answer = answer(&raw_query, [1, 2, 3, 4]);

    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_dns_validate(
            raw_query.as_ptr(),
            raw_query.len(),
            raw_answer.as_ptr(),
            raw_answer.len(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_OK);
    let payload = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
    unsafe { diting_dns_free_bytes(out, out_len) };
    assert_eq!(decode_validation(&payload), Some((0, 0)));

    let (status, payload) = call_payload(diting_dns_extract, &raw_answer);
    assert_eq!(status, STATUS_OK);
    let extracted = decode_extracted(&payload).expect("well formed");
    assert_eq!(extracted.resolved_ips, "1.2.3.4");
    assert_eq!(extracted.addresses[0].ttl, 60);
    assert_eq!(extracted.question_name, "example.com.");

    let (status, _) = call_payload(diting_dns_extract, &raw_answer[..14]);
    assert_eq!(status, STATUS_BAD_PAYLOAD);
}

#[test]
fn exported_symbols_reject_bad_arguments() {
    let raw = query("example.com.");
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    unsafe {
        assert_eq!(
            diting_dns_query_info(std::ptr::null(), 0, std::ptr::null_mut(), &mut out_len),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_dns_query_info(raw.as_ptr(), raw.len(), &mut out, std::ptr::null_mut()),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_dns_extract(std::ptr::null(), 1, &mut out, &mut out_len),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_dns_validate(
                raw.as_ptr(),
                raw.len(),
                std::ptr::null(),
                1,
                &mut out,
                &mut out_len
            ),
            STATUS_BAD_ARGUMENT
        );
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

#[test]
fn reply_plans_round_trip_through_the_exported_symbols() {
    let raw_query = query("ads.example.");

    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_dns_reply_block(
            raw_query.as_ptr(),
            raw_query.len(),
            crate::reply::RESPONSE_CUSTOM_IP as u32,
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_OK);
    let payload = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
    unsafe { diting_dns_free_bytes(out, out_len) };
    let plan = decode_reply(&payload).expect("plan");
    assert_eq!(plan.rcode, crate::reply::RCODE_SUCCESS);
    assert_eq!(plan.answers.len(), 1);
    assert_eq!(plan.answers[0].rdata, vec![0, 0, 0, 0]);

    let ip = b"140.82.112.3";
    let status = unsafe {
        diting_dns_reply_rewrite_ip(
            raw_query.as_ptr(),
            raw_query.len(),
            ip.as_ptr(),
            ip.len(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_OK);
    let payload = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
    unsafe { diting_dns_free_bytes(out, out_len) };
    let plan = decode_reply(&payload).expect("plan");
    assert!(plan.recursion_available);
    assert_eq!(plan.answers[0].rdata, vec![140, 82, 112, 3]);

    // A query that does not parse is a payload error, never a half-built plan.
    let (status, _) = call_payload(diting_dns_reply_local_asset, &[0u8; 3]);
    assert_eq!(status, STATUS_BAD_PAYLOAD);
}

#[test]
fn rewrite_table_handle_round_trips() {
    let entries = vec![
        ("GitHub.COM.".to_string(), vec!["140.82.112.3".to_string()]),
        (
            "cname.example".to_string(),
            vec!["Target.Example.".to_string()],
        ),
    ];
    let payload = encode_rewrite_entries(&entries);
    let handle = unsafe { diting_dns_rewrite_new(payload.as_ptr(), payload.len()) };
    assert!(!handle.is_null());

    let lookup = |domain: &str| {
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut out_len = 0usize;
        let status = unsafe {
            diting_dns_rewrite_lookup(
                handle,
                domain.as_ptr(),
                domain.len(),
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(status, STATUS_OK);
        let payload = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
        unsafe { diting_dns_free_bytes(out, out_len) };
        decode_lookup(&payload).expect("lookup")
    };

    let hit = lookup("www.github.com").expect("hit");
    assert_eq!(hit.ip4, "140.82.112.3");
    let cname = lookup("cname.example").expect("cname");
    assert_eq!(cname.cname, "target.example");
    assert_eq!(lookup("unrelated.test"), None);

    let null_status = unsafe {
        let mut null_out: *mut u8 = std::ptr::null_mut();
        let mut null_len = 0usize;
        diting_dns_rewrite_lookup(
            std::ptr::null(),
            b"x".as_ptr(),
            1,
            &mut null_out,
            &mut null_len,
        )
    };
    assert_eq!(null_status, STATUS_BAD_ARGUMENT);

    unsafe { diting_dns_rewrite_free(handle) };
    assert!(unsafe { diting_dns_rewrite_new(std::ptr::null(), 1) }.is_null());
}

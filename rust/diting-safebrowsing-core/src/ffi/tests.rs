//! The C ABI surface the Go loader drives: null handles, skip, apply statuses and the payload
//! round trip through raw pointers.

use super::*;
use crate::engine::{SAFE_BROWSING_SUFFIX, SERVICE_SAFE_BROWSING};
use crate::payload::decode_plan;

fn plan_call(engine: &Engine, service: u32, host: &str, now_ms: i64) -> Option<crate::Plan> {
    let mut out = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_sb_plan(
            engine as *const Engine,
            service,
            host.as_ptr(),
            host.len(),
            now_ms,
            &mut out,
            &mut out_len,
        )
    };
    if status == PLAN_SKIP {
        assert!(out.is_null());
        assert_eq!(out_len, 0);
        return None;
    }
    assert_eq!(status, PLAN_OK);
    let bytes = unsafe { slice::from_raw_parts(out, out_len).to_vec() };
    unsafe { diting_sb_free_bytes(out, out_len) };
    Some(decode_plan(&bytes).expect("plan payload"))
}

fn apply_request(service: u8, queried: &[[u8; 32]], received: &[&str]) -> Vec<u8> {
    let mut out = vec![crate::payload::LAYOUT_VERSION, service, queried.len() as u8];
    for hash in queried {
        out.extend_from_slice(hash);
    }
    out.extend_from_slice(&(received.len() as u16).to_le_bytes());
    for text in received {
        out.extend_from_slice(&(text.len() as u16).to_le_bytes());
        out.extend_from_slice(text.as_bytes());
    }
    out
}

fn apply_call(engine: &Engine, request: &[u8], now_ms: i64) -> u32 {
    unsafe {
        diting_sb_apply(
            engine as *const Engine,
            request.as_ptr(),
            request.len(),
            now_ms,
        )
    }
}

#[test]
fn abi_version_is_stable() {
    assert_eq!(diting_sb_abi_version(), ABI_VERSION);
}

fn new_handle(cache_size: i64, cache_ttl_ms: i64) -> *mut Engine {
    let mut handle = std::ptr::null_mut();
    let status = unsafe { diting_sb_new(cache_size, cache_ttl_ms, &mut handle) };
    assert_eq!(status, 1);
    assert!(!handle.is_null());
    handle
}

#[test]
fn handle_round_trip_blocks_a_listed_host() {
    let handle = new_handle(16, 600_000);
    let engine = unsafe { handle.as_ref() }.expect("handle");

    let plan = plan_call(engine, SERVICE_SAFE_BROWSING.into(), "host.com", 1_000).expect("plan");
    assert!(plan.question.ends_with(SAFE_BROWSING_SUFFIX));
    let queried: Vec<[u8; 32]> = plan.need_query.clone();

    // The third party answers with the full digest of "host.com".
    let listed = plan.need_query[0];
    let hex: String = listed.iter().map(|byte| format!("{byte:02x}")).collect();
    let request = apply_request(SERVICE_SAFE_BROWSING, &queried, &[hex.as_str()]);
    assert_eq!(apply_call(engine, &request, 1_000), APPLY_BLOCK);

    let cached = plan_call(engine, SERVICE_SAFE_BROWSING.into(), "host.com", 1_001).expect("plan");
    assert!(cached.found);
    assert!(cached.blocked);

    unsafe { diting_sb_configure(handle, 16, 700_000) };
    unsafe { diting_sb_free(handle) };
}

#[test]
fn invalid_host_reports_skip() {
    let handle = new_handle(16, 600_000);
    let engine = unsafe { handle.as_ref() }.expect("handle");
    assert!(plan_call(engine, SERVICE_SAFE_BROWSING.into(), "  ", 0).is_none());
    assert!(
        plan_call(engine, 9, "host.com", 0).is_none(),
        "unknown service"
    );
    unsafe { diting_sb_free(handle) };
}

#[test]
fn null_out_pointer_is_rejected() {
    assert_eq!(unsafe { diting_sb_new(1, 1, std::ptr::null_mut()) }, 0);
}

#[test]
fn null_handle_is_a_no_op() {
    let mut out = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_sb_plan(
            std::ptr::null(),
            0,
            "host.com".as_ptr(),
            "host.com".len(),
            0,
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, PLAN_SKIP);
    assert_eq!(
        unsafe { diting_sb_apply(std::ptr::null(), std::ptr::null(), 0, 0) },
        APPLY_PASS
    );
    unsafe { diting_sb_configure(std::ptr::null(), 1, 1) };
    unsafe { diting_sb_free(std::ptr::null_mut()) };
    unsafe { diting_sb_free_bytes(std::ptr::null_mut(), 0) };
}

#[test]
fn undecodable_request_is_reported() {
    let handle = new_handle(16, 600_000);
    let engine = unsafe { handle.as_ref() }.expect("handle");

    let mut encoded = apply_request(SERVICE_SAFE_BROWSING, &[], &[]);
    encoded[0] = 99;
    assert_eq!(apply_call(engine, &encoded, 0), APPLY_BAD_REQUEST);
    assert_eq!(apply_call(engine, &[], 0), APPLY_BAD_REQUEST);

    unsafe { diting_sb_free(handle) };
}

#[test]
fn unlisted_answer_passes_and_is_cached() {
    let handle = new_handle(16, 600_000);
    let engine = unsafe { handle.as_ref() }.expect("handle");

    let plan = plan_call(engine, SERVICE_SAFE_BROWSING.into(), "host.com", 0).expect("plan");
    let request = apply_request(SERVICE_SAFE_BROWSING, &plan.need_query, &[]);
    assert_eq!(apply_call(engine, &request, 0), APPLY_PASS);

    let cached = plan_call(engine, SERVICE_SAFE_BROWSING.into(), "host.com", 1).expect("plan");
    assert!(cached.found);
    assert!(!cached.blocked);
    assert!(cached.need_query.is_empty());

    unsafe { diting_sb_free(handle) };
}

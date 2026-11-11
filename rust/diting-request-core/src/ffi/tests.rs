//! The exported entry points and the handle lifecycle.

use super::*;
use std::slice;

fn push_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn new_handle(rules: &[(&str, &str)]) -> *mut RuleSet {
    let mut payload = Vec::new();
    payload.extend_from_slice(&(rules.len() as i64).to_le_bytes());
    for (kind, pattern) in rules {
        push_text(&mut payload, kind);
        push_text(&mut payload, pattern);
    }
    let mut handle: *mut RuleSet = std::ptr::null_mut();
    let status = unsafe { diting_request_new(payload.as_ptr(), payload.len(), &mut handle) };
    assert_eq!(status, STATUS_OK);
    assert!(!handle.is_null());
    handle
}

struct Decision {
    matched: i64,
    blocked: i64,
    pattern: String,
    domain_host: String,
}

fn match_request(handle: *mut RuleSet, scheme: &str, host: &str, path: &str) -> Decision {
    let mut payload = Vec::new();
    push_text(&mut payload, scheme);
    push_text(&mut payload, host);
    push_text(&mut payload, path);
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len: usize = 0;
    let status = unsafe {
        diting_request_match(
            handle,
            payload.as_ptr(),
            payload.len(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_OK);
    let body = unsafe { slice::from_raw_parts(out, out_len).to_vec() };
    unsafe { diting_request_free_bytes(out, out_len) };

    let mut position = 0;
    let take_i64 = |position: &mut usize| {
        let value = i64::from_le_bytes(body[*position..*position + 8].try_into().unwrap());
        *position += 8;
        value
    };
    let matched = take_i64(&mut position);
    let blocked = take_i64(&mut position);
    let take_text = |position: &mut usize| {
        let length =
            u32::from_le_bytes(body[*position..*position + 4].try_into().unwrap()) as usize;
        *position += 4;
        let text = String::from_utf8(body[*position..*position + length].to_vec()).unwrap();
        *position += length;
        text
    };
    let pattern = take_text(&mut position);
    let domain_host = take_text(&mut position);
    assert_eq!(position, body.len());
    Decision {
        matched,
        blocked,
        pattern,
        domain_host,
    }
}

#[test]
fn abi_version_is_published() {
    assert_eq!(diting_request_abi_version(), ABI_VERSION);
}

#[test]
fn a_handle_decides_requests() {
    let handle = new_handle(&[
        ("block", "https://ads.example/spy"),
        ("allow", "https://ads.example/spy/allowed"),
    ]);
    let decision = match_request(handle, "https", "ads.example", "/spy");
    assert_eq!((decision.matched, decision.blocked), (1, 1));
    assert_eq!(decision.pattern, "https://ads.example/spy");
    assert_eq!(decision.domain_host, "ads.example");

    let decision = match_request(handle, "https", "ads.example", "/spy/allowed");
    assert_eq!((decision.matched, decision.blocked), (1, 0));
    assert_eq!(decision.pattern, "https://ads.example/spy/allowed");

    let decision = match_request(handle, "http", "other.example", "/x");
    assert_eq!((decision.matched, decision.blocked), (0, 0));
    assert_eq!(decision.pattern, "");
    assert_eq!(decision.domain_host, "other.example");
    unsafe { diting_request_close(handle) };
}

#[test]
fn an_empty_rule_set_still_answers() {
    let handle = new_handle(&[]);
    let decision = match_request(handle, "https", "a.example", "/");
    assert_eq!((decision.matched, decision.blocked), (0, 0));
    assert_eq!(decision.domain_host, "a.example");
    unsafe { diting_request_close(handle) };
}

#[test]
fn bad_arguments_and_bad_payloads_are_status_codes() {
    let mut handle: *mut RuleSet = std::ptr::null_mut();
    assert_eq!(
        unsafe { diting_request_new(std::ptr::null(), 0, std::ptr::null_mut()) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_request_new([0u8].as_ptr(), 1, &mut handle) },
        STATUS_BAD_PAYLOAD
    );
    assert!(handle.is_null());

    let handle = new_handle(&[("block", "https://a.example/x")]);
    let mut out_len: usize = 0;
    let mut out: *mut u8 = std::ptr::null_mut();
    assert_eq!(
        unsafe {
            diting_request_match(std::ptr::null(), [0u8].as_ptr(), 1, &mut out, &mut out_len)
        },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_request_match(handle, [0xffu8].as_ptr(), 1, &mut out, &mut out_len) },
        STATUS_BAD_PAYLOAD
    );
    assert_eq!(
        unsafe { diting_request_match(handle, std::ptr::null(), 1, &mut out, &mut out_len) },
        STATUS_BAD_ARGUMENT
    );
    unsafe { diting_request_close(handle) };
    // Closing a null handle is a no-op.
    unsafe { diting_request_close(std::ptr::null_mut()) };
    unsafe { diting_request_free_bytes(std::ptr::null_mut(), 0) };
}

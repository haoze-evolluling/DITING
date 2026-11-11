//! The C ABI surface: request decode, reply encode, status words and the type list.

use std::slice;

use super::*;
use crate::payload::{encode_reply, LAYOUT_VERSION};
use crate::record::build;

/// A request payload in the layout `rewrite_native.go` writes.
fn request(qtype: u16, ttl: u32, name: &str, type_name: &str, value: &str) -> Vec<u8> {
    fn push_text(out: &mut Vec<u8>, value: &str) {
        out.extend_from_slice(&(value.len() as u32).to_le_bytes());
        out.extend_from_slice(value.as_bytes());
    }
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&qtype.to_le_bytes());
    out.extend_from_slice(&ttl.to_le_bytes());
    push_text(&mut out, name);
    push_text(&mut out, type_name);
    push_text(&mut out, value);
    out
}

#[test]
fn abi_is_advertised() {
    assert_eq!(diting_rewrite_abi_version(), ABI_VERSION);
}

#[test]
fn a_record_crosses_the_boundary_field_by_field() {
    let payload = request(1, 60, "host.lan", "A", "10.0.0.1");
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_rewrite_build_record(payload.as_ptr(), payload.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);

    let reply = unsafe { payload_slice(out, out_len) };
    // layout, has_record, rrtype, owner (u32 length + bytes), ttl, address.
    assert_eq!(reply[0], LAYOUT_VERSION);
    assert_eq!(reply[1], 1);
    assert_eq!(&reply[2..4], &1u16.to_le_bytes());
    assert_eq!(&reply[4..8], &9u32.to_le_bytes());
    assert_eq!(&reply[8..17], b"host.lan.");
    assert_eq!(&reply[17..21], &60u32.to_le_bytes());
    assert_eq!(&reply[21..25], &[10, 0, 0, 1]);
    assert_eq!(reply.len(), 25);
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn a_type_mismatch_is_a_reply_not_an_error() {
    // An MX record asked for with qtype A: the caller must see "no record", not a failure.
    let reply = encode_reply(
        build("host.lan", 1, "MX", "32 mail.lan", 60)
            .unwrap()
            .as_ref(),
    );
    assert_eq!(reply, vec![LAYOUT_VERSION, 0]);
}

#[test]
fn an_invalid_value_reports_its_message() {
    let payload = request(28, 60, "bad6.lan", "AAAA", "10.0.0.5");
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_rewrite_build_record(payload.as_ptr(), payload.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_REJECTED);
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec())
        .expect("message is UTF-8");
    assert!(message.contains("不是合法的 IPv6 地址"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn a_malformed_request_is_rejected() {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;

    let wrong_layout = [LAYOUT_VERSION + 1, 1, 0, 60, 0, 0, 0];
    let status = unsafe {
        diting_rewrite_build_record(
            wrong_layout.as_ptr(),
            wrong_layout.len(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_REJECTED);
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec()).unwrap();
    assert!(message.contains("layout"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    // Trailing bytes mean the two sides disagree about the layout.
    let mut trailing = request(1, 60, "host.lan", "A", "10.0.0.1");
    trailing.push(0xEE);
    let status = unsafe {
        diting_rewrite_build_record(trailing.as_ptr(), trailing.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_REJECTED);
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec()).unwrap();
    assert!(message.contains("trailing"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn the_type_list_crosses_the_boundary_sorted() {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe { diting_rewrite_record_types(&mut out, &mut out_len) };
    assert_eq!(status, STATUS_OK);

    let reply = unsafe { payload_slice(out, out_len) };
    assert_eq!(reply[0], LAYOUT_VERSION);
    assert_eq!(&reply[1..3], &10u16.to_le_bytes());
    // Sorted, `u32`-length strings: A, AAAA, CNAME, HTTPS, MX, NS, PTR, SRV, SVCB, TXT.
    assert_eq!(&reply[3..8], &[1, 0, 0, 0, b'A']);
    assert_eq!(&reply[8..16], &[4, 0, 0, 0, b'A', b'A', b'A', b'A']);
    assert!(reply.len() > 16);
    let tail = &reply[reply.len() - 7..];
    assert_eq!(tail, &[3, 0, 0, 0, b'T', b'X', b'T']);
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn bad_arguments_are_reported() {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status =
        unsafe { diting_rewrite_build_record(std::ptr::null(), 4, &mut out, &mut out_len) };
    assert_eq!(status, STATUS_BAD_ARGS);
    let status = unsafe {
        diting_rewrite_build_record(std::ptr::null(), 0, std::ptr::null_mut(), &mut out_len)
    };
    assert_eq!(status, STATUS_BAD_ARGS);
    let status = unsafe { diting_rewrite_record_types(std::ptr::null_mut(), &mut out_len) };
    assert_eq!(status, STATUS_BAD_ARGS);
    // Freeing null is a no-op rather than a crash.
    unsafe { diting_rewrite_free_bytes(std::ptr::null_mut(), 0) };
}

#[test]
fn a_rewrite_value_crosses_the_boundary_field_by_field() {
    let mut payload = vec![LAYOUT_VERSION];
    payload.extend_from_slice(&(9u32).to_le_bytes());
    payload.extend_from_slice(b"127.0.0.1");

    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_rewrite_parse_action(payload.as_ptr(), payload.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);

    let reply = unsafe { payload_slice(out, out_len) };
    // layout, bare, rcode, rrtype, value (u32 length + bytes).
    assert_eq!(reply[0], LAYOUT_VERSION);
    assert_eq!(reply[1], 0, "not bare");
    assert_eq!(&reply[2..4], &0u16.to_le_bytes());
    assert_eq!(&reply[4..6], &1u16.to_le_bytes(), "A record");
    assert_eq!(&reply[6..10], &9u32.to_le_bytes());
    assert_eq!(&reply[10..19], b"127.0.0.1");
    assert_eq!(reply.len(), 19);
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn a_rejected_rewrite_value_reports_its_message() {
    let mut payload = vec![LAYOUT_VERSION];
    payload.extend_from_slice(&(14u32).to_le_bytes());
    payload.extend_from_slice(b"NOERROR;A;nope");

    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_rewrite_parse_action(payload.as_ptr(), payload.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_REJECTED);
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec())
        .expect("message is UTF-8");
    assert!(message.contains("不是合法的 IPv4 地址"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn the_action_key_crosses_the_boundary_normalized() {
    // An IPv4-mapped literal must key like the plain address it maps to.
    let mut payload = vec![LAYOUT_VERSION, 0];
    payload.extend_from_slice(&0u16.to_le_bytes());
    payload.extend_from_slice(&1u16.to_le_bytes());
    payload.extend_from_slice(&(15u32).to_le_bytes());
    payload.extend_from_slice(b"::ffff:10.0.0.1");

    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_rewrite_action_key(payload.as_ptr(), payload.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);

    let reply = unsafe { payload_slice(out, out_len) };
    assert_eq!(reply[0], LAYOUT_VERSION);
    assert_eq!(&reply[1..5], &(12u32).to_le_bytes());
    assert_eq!(&reply[5..17], b"0;1;10.0.0.1");
    assert_eq!(reply.len(), 17);
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    // A bare action keys as `bare` without touching the value.
    let mut bare = vec![LAYOUT_VERSION, 1];
    bare.extend_from_slice(&0u16.to_le_bytes());
    bare.extend_from_slice(&0u16.to_le_bytes());
    bare.extend_from_slice(&(4u32).to_le_bytes());
    bare.extend_from_slice(b"junk");
    let status =
        unsafe { diting_rewrite_action_key(bare.as_ptr(), bare.len(), &mut out, &mut out_len) };
    assert_eq!(status, STATUS_OK);
    let reply = unsafe { payload_slice(out, out_len) };
    assert_eq!(&reply[1..5], &(4u32).to_le_bytes());
    assert_eq!(&reply[5..9], b"bare");
    unsafe { diting_rewrite_free_bytes(out, out_len) };
}

#[test]
fn action_requests_reject_a_mismatched_layout() {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;

    let wrong_layout = [LAYOUT_VERSION + 1, 0, 0, 0, 0];
    let status = unsafe {
        diting_rewrite_parse_action(
            wrong_layout.as_ptr(),
            wrong_layout.len(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_REJECTED);
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec()).unwrap();
    assert!(message.contains("layout"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    // An unknown flag in the action fields is a layout mismatch too.
    let unknown_flag = [LAYOUT_VERSION, 2, 0, 0, 0, 0];
    let status = unsafe {
        diting_rewrite_action_key(
            unknown_flag.as_ptr(),
            unknown_flag.len(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_REJECTED);
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec()).unwrap();
    assert!(message.contains("bare flag"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    let status =
        unsafe { diting_rewrite_parse_action(std::ptr::null(), 4, &mut out, &mut out_len) };
    assert_eq!(status, STATUS_BAD_ARGS);
    let status = unsafe {
        diting_rewrite_action_key(std::ptr::null(), 0, std::ptr::null_mut(), &mut out_len)
    };
    assert_eq!(status, STATUS_BAD_ARGS);
}

/// Rebuilds the byte slice the library handed out.
unsafe fn payload_slice(pointer: *mut u8, length: usize) -> &'static [u8] {
    if pointer.is_null() || length == 0 {
        return &[];
    }
    slice::from_raw_parts(pointer, length)
}

/// One engine config: enabled, TTL 60, one exact rule with one IPv4 shortcut.
fn engine_request() -> Vec<u8> {
    fn push_text(out: &mut Vec<u8>, value: &str) {
        out.extend_from_slice(&(value.len() as u32).to_le_bytes());
        out.extend_from_slice(value.as_bytes());
    }
    let mut out = vec![LAYOUT_VERSION, 1];
    out.extend_from_slice(&60u32.to_le_bytes());
    out.extend_from_slice(&1u32.to_le_bytes());
    push_text(&mut out, "nas.lan");
    out.extend_from_slice(&0u32.to_le_bytes()); // rule TTL: engine default
    out.extend_from_slice(&1u32.to_le_bytes()); // one IP
    push_text(&mut out, "192.168.1.100");
    push_text(&mut out, ""); // no shortcut CNAME
    out.extend_from_slice(&0u32.to_le_bytes()); // no shortcut TXT
    out.extend_from_slice(&0u32.to_le_bytes()); // no explicit records
    push_text(&mut out, ""); // no rcode override
    out
}

#[test]
fn an_engine_handle_answers_lookup_ptr_and_reverse() {
    let request = engine_request();
    let mut handle: *mut Engine = std::ptr::null_mut();
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_rewrite_engine_build(
            request.as_ptr(),
            request.len(),
            &mut handle,
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_OK);
    assert!(!handle.is_null());
    let warnings = unsafe { payload_slice(out, out_len) };
    assert_eq!(&warnings[..5], &[LAYOUT_VERSION, 0, 0, 0, 0]);
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    let name = "nas.lan";
    let status = unsafe {
        diting_rewrite_engine_lookup(handle, name.as_ptr(), name.len(), 1, &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);
    let reply = unsafe { payload_slice(out, out_len) };
    assert_eq!(reply[0], LAYOUT_VERSION);
    assert_eq!(reply[1], 1, "matched");
    assert_eq!(&reply[2..4], &0u16.to_le_bytes(), "rcode");
    assert_eq!(&reply[4..8], &1u32.to_le_bytes(), "one answer");
    assert_eq!(&reply[8..10], &1u16.to_le_bytes(), "A record");
    let owner_len = u32::from_le_bytes(reply[10..14].try_into().unwrap()) as usize;
    assert_eq!(&reply[14..14 + owner_len], b"nas.lan.");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    let ip = [192u8, 168, 1, 100];
    let status = unsafe {
        diting_rewrite_engine_ptr_lookup(handle, ip.as_ptr(), ip.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);
    let reply = unsafe { payload_slice(out, out_len) };
    assert_eq!(&reply[..5], &[LAYOUT_VERSION, 1, 0, 0, 0]);
    assert_eq!(&reply[9..11], b"na");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    let status = unsafe {
        diting_rewrite_engine_reverse_lookup(handle, ip.as_ptr(), ip.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);
    let reply = unsafe { payload_slice(out, out_len) };
    assert_eq!(reply[0], LAYOUT_VERSION);
    assert_eq!(reply[1], 1, "present");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    unsafe { diting_rewrite_engine_free(handle) };
}

#[test]
fn an_engine_build_rejects_a_mismatched_layout_and_bad_arguments() {
    let mut handle: *mut Engine = std::ptr::null_mut();
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;

    let wrong_layout = [LAYOUT_VERSION + 1, 1, 0, 0, 0];
    let status = unsafe {
        diting_rewrite_engine_build(
            wrong_layout.as_ptr(),
            wrong_layout.len(),
            &mut handle,
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_REJECTED);
    assert!(handle.is_null());
    let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec()).unwrap();
    assert!(message.contains("layout"), "{message}");
    unsafe { diting_rewrite_free_bytes(out, out_len) };

    let status = unsafe {
        diting_rewrite_engine_build(
            std::ptr::null(),
            0,
            std::ptr::null_mut(),
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_BAD_ARGS);
    let status = unsafe {
        diting_rewrite_engine_lookup(
            std::ptr::null_mut(),
            std::ptr::null(),
            0,
            1,
            &mut out,
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_BAD_ARGS);
    unsafe { diting_rewrite_engine_free(std::ptr::null_mut()) };
}

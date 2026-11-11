//! ABI round-trips: every entry point through the raw pointers the Go side passes.

use super::*;
use crate::hosts::Source;
use crate::payload::{decode_sources, encode_sources, Reader, LAYOUT_VERSION};

fn build(sources: &[Source]) -> *mut HostsTable {
    let payload = encode_sources(sources);
    let mut handle: *mut HostsTable = std::ptr::null_mut();
    let status = unsafe { diting_hosts_new(payload.as_ptr(), payload.len(), &mut handle) };
    assert_eq!(status, 1);
    assert!(!handle.is_null());
    handle
}

fn take_payload(out: *mut u8, len: usize) -> Vec<u8> {
    assert!(!out.is_null());
    let payload = unsafe { std::slice::from_raw_parts(out, len).to_vec() };
    unsafe { diting_hosts_free_bytes(out, len) };
    payload
}

fn lookup(handle: *mut HostsTable, host: &str, qtype: u16) -> Vec<u8> {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    let status = unsafe {
        diting_hosts_lookup(handle, host.as_ptr(), host.len(), qtype, &mut out, &mut len)
    };
    assert_eq!(status, 1);
    take_payload(out, len)
}

fn address_bytes(payload: &[u8]) -> Vec<Vec<u8>> {
    let mut reader = Reader::new(payload);
    reader.layout("lookup").expect("layout");
    let width = reader.u8("width").expect("width") as usize;
    let count = reader.u32("count").expect("count") as usize;
    let mut out = Vec::new();
    for _ in 0..count {
        out.push(reader.bytes(width, "addr").expect("addr").to_vec());
    }
    assert_eq!(reader.remaining(), 0);
    out
}

#[test]
fn version_matches_the_header() {
    assert_eq!(diting_hosts_abi_version(), ABI_VERSION);
}

#[test]
fn build_info_and_free() {
    let handle = build(&[Source::Text("127.0.0.1 localhost\n".to_string())]);
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(unsafe { diting_hosts_info(handle, &mut out, &mut len) }, 1);
    let payload = take_payload(out, len);
    let mut reader = Reader::new(&payload);
    reader.layout("info").expect("layout");
    assert_eq!(reader.u8("has_error").expect("flag"), 0);
    assert_eq!(reader.text().expect("error"), "");
    assert_eq!(reader.u32("count").expect("count"), 0);
    assert!(reader.expect_end().is_ok());
    unsafe { diting_hosts_free(handle) };
}

#[test]
fn lookups_answer_and_miss() {
    let handle = build(&[Source::Text(
        "127.0.0.1 localhost\n::1 localhost\n".to_string(),
    )]);
    assert_eq!(
        address_bytes(&lookup(handle, "LOCALHOST.", 1)),
        vec![vec![127, 0, 0, 1]]
    );
    assert_eq!(
        address_bytes(&lookup(handle, "IP6-LOCALHOST", 28)),
        Vec::<Vec<u8>>::new()
    );
    let v6 = address_bytes(&lookup(handle, "localhost", 28));
    assert_eq!(v6.len(), 1);
    assert_eq!(v6[0].len(), 16);
    assert_eq!(v6[0][15], 1);
    assert_eq!(
        address_bytes(&lookup(handle, "nope", 1)),
        Vec::<Vec<u8>>::new()
    );
    unsafe { diting_hosts_free(handle) };
}

#[test]
fn contains_answers_the_boolean() {
    let handle = build(&[Source::Text("127.0.0.1 localhost\n".to_string())]);
    let present = "localhost";
    let absent = "nope";
    assert_eq!(
        unsafe { diting_hosts_contains(handle, present.as_ptr(), present.len()) },
        1
    );
    assert_eq!(
        unsafe { diting_hosts_contains(handle, absent.as_ptr(), absent.len()) },
        0
    );
    unsafe { diting_hosts_free(handle) };
}

#[test]
fn ptr_and_reverse_read_the_same_map() {
    let handle = build(&[Source::Text(
        "192.168.1.100 nas.home storage.home\n".to_string(),
    )]);
    let arpa = "100.1.168.192.in-addr.arpa.";
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_hosts_ptr(handle, arpa.as_ptr(), arpa.len(), &mut out, &mut len) },
        1
    );
    let payload = take_payload(out, len);
    let mut reader = Reader::new(&payload);
    reader.layout("names").expect("layout");
    assert_eq!(reader.u32("count").expect("count"), 2);
    assert_eq!(reader.text().expect("first"), "nas.home");
    assert_eq!(reader.text().expect("second"), "storage.home");
    assert!(reader.expect_end().is_ok());

    let address = [192u8, 168, 1, 100];
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe {
            diting_hosts_reverse(handle, address.as_ptr(), address.len(), &mut out, &mut len)
        },
        1
    );
    let payload = take_payload(out, len);
    assert_eq!(&payload[..2], &[crate::payload::LAYOUT_VERSION, 1]);
    assert!(payload.ends_with(b"nas.home"));

    // A 5-byte "address" is not an address.
    let bad = [0u8; 5];
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_hosts_reverse(handle, bad.as_ptr(), bad.len(), &mut out, &mut len) },
        0
    );
    unsafe { diting_hosts_free(handle) };
}

#[test]
fn parse_arpa_needs_no_table() {
    let name = "1.1.168.192.in-addr.arpa.";
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_hosts_parse_arpa(name.as_ptr(), name.len(), &mut out, &mut len) },
        1
    );
    assert_eq!(
        take_payload(out, len),
        [crate::payload::LAYOUT_VERSION, 4, 192, 168, 1, 1]
    );

    let name = "example.com.";
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_hosts_parse_arpa(name.as_ptr(), name.len(), &mut out, &mut len) },
        1
    );
    assert_eq!(take_payload(out, len), [crate::payload::LAYOUT_VERSION, 0]);
}

#[test]
fn bad_arguments_are_rejected() {
    let mut handle: *mut HostsTable = std::ptr::null_mut();
    // A payload that does not decode must not produce a handle.
    let garbage = [LAYOUT_VERSION, 9, 0, 0, 0, 0];
    assert_eq!(
        unsafe { diting_hosts_new(garbage.as_ptr(), garbage.len(), &mut handle) },
        0
    );
    assert!(handle.is_null());
    assert_eq!(
        unsafe { diting_hosts_new(std::ptr::null(), 0, &mut handle) },
        0
    );
    // A null out-parameter is a rejection, not a crash.
    assert_eq!(
        unsafe { diting_hosts_new(std::ptr::null(), 0, std::ptr::null_mut()) },
        0
    );

    // Every read on a null handle is a miss.
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_hosts_info(std::ptr::null(), &mut out, &mut len) },
        0
    );
    assert_eq!(
        unsafe { diting_hosts_lookup(std::ptr::null(), b"x".as_ptr(), 0, 1, &mut out, &mut len) },
        0
    );
    assert_eq!(
        unsafe { diting_hosts_contains(std::ptr::null(), b"x".as_ptr(), 0) },
        0
    );
    assert_eq!(
        unsafe { diting_hosts_ptr(std::ptr::null(), b"x".as_ptr(), 0, &mut out, &mut len) },
        0
    );

    // Invalid UTF-8 is rejected rather than silently lossy.
    let handle = build(&[Source::Text("127.0.0.1 localhost\n".to_string())]);
    let invalid = [0xffu8, 0xfe];
    assert_eq!(
        unsafe {
            diting_hosts_lookup(
                handle,
                invalid.as_ptr(),
                invalid.len(),
                1,
                &mut out,
                &mut len,
            )
        },
        0
    );
    assert_eq!(
        unsafe { diting_hosts_parse_arpa(invalid.as_ptr(), invalid.len(), &mut out, &mut len) },
        0
    );
    unsafe { diting_hosts_free(handle) };
}

#[test]
fn a_null_handle_can_still_be_freed() {
    unsafe { diting_hosts_free(std::ptr::null_mut()) };
    unsafe { diting_hosts_free_bytes(std::ptr::null_mut(), 0) };
}

#[test]
fn an_empty_source_list_builds_an_empty_table() {
    let handle = build(&[]);
    assert_eq!(
        address_bytes(&lookup(handle, "localhost", 1)),
        Vec::<Vec<u8>>::new()
    );
    unsafe { diting_hosts_free(handle) };
}

#[test]
fn decode_sources_sees_what_the_encoder_wrote() {
    let sources = vec![Source::Text("x".to_string())];
    assert_eq!(
        decode_sources(&encode_sources(&sources)).expect("decode"),
        sources
    );
}

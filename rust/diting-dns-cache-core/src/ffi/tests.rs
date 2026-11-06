//! The C ABI surface: handle lifecycle, payload layouts and rejection codes.

use std::slice;

use super::*;
use crate::payload::{decode_config, LAYOUT_VERSION};
use crate::policy::{Config, TtlMode};

const CLASS_IN: u16 = 1;
const TYPE_A: u16 = 1;

const TYPE_AAAA: u16 = 28;

fn name_wire(name: &str) -> Vec<u8> {
    let trimmed = name.trim_end_matches('.');
    let mut out = Vec::new();
    if trimmed.is_empty() {
        out.push(0);
        return out;
    }
    for label in trimmed.split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out
}

fn query_message(name: &str, qtype: u16) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x1234u16.to_be_bytes());
    out.extend(0x0100u16.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire(name));
    out.extend(qtype.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    out
}

fn record(name: &str, rrtype: u16, ttl: u32, rdata: &[u8]) -> Vec<u8> {
    let mut out = name_wire(name);
    out.extend(rrtype.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    out.extend(ttl.to_be_bytes());
    out.extend((rdata.len() as u16).to_be_bytes());
    out.extend_from_slice(rdata);
    out
}

fn answer(name: &str, answers: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x2222u16.to_be_bytes());
    out.extend(0x8180u16.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend((answers.len() as u16).to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire(name));
    out.extend(TYPE_A.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    for rr in answers {
        out.extend_from_slice(rr);
    }
    out
}

fn test_config(enabled: bool, stale: bool) -> Vec<u8> {
    encode_test_config(
        &Config {
            enabled,
            stale_fallback_enabled: stale,
            stale_fallback_seconds: 30,
            ..Config::default()
        },
        "follow_dns_ttl",
    )
}

unsafe fn payload_slice(pointer: *const u8, length: usize) -> &'static [u8] {
    slice::from_raw_parts(pointer, length)
}

/// Offset of the first answer's TTL in a response built by [`answer`].
fn ttl_at(wire: &[u8], name: &str) -> u32 {
    let offset = 12 + name_wire(name).len() + 4 + name_wire(name).len() + 4;
    u32::from_be_bytes([
        wire[offset],
        wire[offset + 1],
        wire[offset + 2],
        wire[offset + 3],
    ])
}

struct Handle {
    raw: *mut Cache,
    flags: u8,
}

impl Drop for Handle {
    fn drop(&mut self) {
        unsafe {
            diting_dns_cache_close(self.raw);
            diting_dns_cache_free(self.raw);
        }
    }
}

fn build(config: &[u8]) -> Handle {
    let mut flags = 0u8;
    let mut message: *mut u8 = std::ptr::null_mut();
    let mut message_len = 0usize;
    let raw = unsafe {
        diting_dns_cache_new(
            config.as_ptr(),
            config.len(),
            &mut flags,
            &mut message,
            &mut message_len,
        )
    };
    if !message.is_null() {
        unsafe { diting_dns_cache_free_bytes(message, message_len) };
    }
    assert!(!raw.is_null(), "cache handle was refused");
    Handle { raw, flags }
}

#[test]
fn abi_is_advertised() {
    assert_eq!(diting_dns_cache_abi_version(), ABI_VERSION);
}

#[test]
fn question_key_crosses_the_boundary() {
    let wire = query_message("Example.COM.", TYPE_AAAA);
    let mut key = vec![0u8; wire::MAX_KEY_LEN];
    let mut name_len = 0u32;
    let mut qtype = 0u16;
    let mut qclass = 0u16;
    let length = unsafe {
        diting_dns_cache_question_key(
            wire.as_ptr(),
            wire.len(),
            key.as_mut_ptr(),
            key.len(),
            &mut name_len,
            &mut qtype,
            &mut qclass,
        )
    };
    assert_eq!(length, 16);
    assert_eq!(&key[..16], b"example.com:28:1");
    assert_eq!(name_len, 11);
    assert_eq!(qtype, TYPE_AAAA);
    assert_eq!(qclass, CLASS_IN);
}

#[test]
fn question_key_reports_a_small_buffer_and_bad_input() {
    let wire = query_message("example.com.", TYPE_A);
    let mut name_len = 0u32;
    let mut qtype = 0u16;
    let mut qclass = 0u16;
    let mut tiny = vec![0u8; 4];
    let length = unsafe {
        diting_dns_cache_question_key(
            wire.as_ptr(),
            wire.len(),
            tiny.as_mut_ptr(),
            tiny.len(),
            &mut name_len,
            &mut qtype,
            &mut qclass,
        )
    };
    assert_eq!(length, LENGTH_TOO_SMALL);

    let truncated = [0u8; 8];
    let mut key = vec![0u8; wire::MAX_KEY_LEN];
    let length = unsafe {
        diting_dns_cache_question_key(
            truncated.as_ptr(),
            truncated.len(),
            key.as_mut_ptr(),
            key.len(),
            &mut name_len,
            &mut qtype,
            &mut qclass,
        )
    };
    assert_eq!(length, LENGTH_INVALID);

    let length = unsafe {
        diting_dns_cache_question_key(
            wire.as_ptr(),
            wire.len(),
            std::ptr::null_mut(),
            0,
            &mut name_len,
            &mut qtype,
            &mut qclass,
        )
    };
    assert_eq!(length, LENGTH_INVALID);
}

#[test]
fn new_rejects_a_bad_config_payload() {
    let mut flags = 0u8;
    let mut message: *mut u8 = std::ptr::null_mut();
    let mut message_len = 0usize;
    let bad = [LAYOUT_VERSION + 1, 0];
    let raw = unsafe {
        diting_dns_cache_new(
            bad.as_ptr(),
            bad.len(),
            &mut flags,
            &mut message,
            &mut message_len,
        )
    };
    assert!(raw.is_null());
    assert!(message_len > 0);
    assert!(!message.is_null());
    unsafe { diting_dns_cache_free_bytes(message, message_len) };
}

#[test]
fn config_payload_reports_the_normalized_flags() {
    let handle = build(&test_config(true, true));
    assert_eq!(
        handle.flags,
        crate::policy::FLAG_ENABLED
            | crate::policy::FLAG_STALE_FALLBACK
            | crate::policy::FLAG_NEGATIVE_TTL
    );

    let config = decode_config(&test_config(false, false)).expect("valid config");
    assert!(!config.enabled);
    assert_eq!(config.mode, TtlMode::FollowDnsTtl);
    assert_eq!(config.stale_fallback_seconds, 30);
}

#[test]
fn put_and_get_round_trip_through_the_boundary() {
    let handle = build(&test_config(true, false));
    let query = query_message("cached.example.", TYPE_A);
    let answers = [record("cached.example.", TYPE_A, 300, &[192, 0, 2, 7])];
    let response = answer("cached.example.", &answers);
    let stored = unsafe {
        diting_dns_cache_put(
            handle.raw,
            query.as_ptr(),
            query.len(),
            response.as_ptr(),
            response.len(),
        )
    };
    assert_eq!(stored, 1);

    let mut patched_query = query.clone();
    patched_query[0] = 0xbe;
    patched_query[1] = 0xef;
    let mut payload: *mut u8 = std::ptr::null_mut();
    let mut payload_len = 0usize;
    let status = unsafe {
        diting_dns_cache_get(
            handle.raw,
            patched_query.as_ptr(),
            patched_query.len(),
            1,
            &mut payload,
            &mut payload_len,
        )
    };
    assert_eq!(status, GET_FRESH);
    let bytes = unsafe { payload_slice(payload, payload_len) };
    assert_eq!(bytes[0], LAYOUT_VERSION);
    assert_eq!(bytes[1], 0); // not stale
    assert_eq!(bytes[2], 0); // not negative
    let wire_len = u32::from_le_bytes([bytes[3], bytes[4], bytes[5], bytes[6]]) as usize;
    let wire = &bytes[7..7 + wire_len];
    assert_eq!(&wire[0..2], &[0xbe, 0xef]);
    let ttl = ttl_at(wire, "cached.example.");
    assert!((299..=300).contains(&ttl), "ttl was {ttl}");
    unsafe { diting_dns_cache_free_bytes(payload, payload_len) };

    // A different query ID and an unknown name behave like the Go cache did.
    let miss = query_message("other.example.", TYPE_A);
    let status = unsafe {
        diting_dns_cache_get(
            handle.raw,
            miss.as_ptr(),
            miss.len(),
            1,
            &mut payload,
            &mut payload_len,
        )
    };
    assert_eq!(status, GET_MISS);
    assert_eq!(payload_len, 0);
}

#[test]
fn stale_status_and_refresh_slot() {
    let handle = build(&test_config(true, true));
    let query = query_message("stale.example.", TYPE_A);
    let answers = [record("stale.example.", TYPE_A, 1, &[192, 0, 2, 8])];
    let response = answer("stale.example.", &answers);
    unsafe {
        diting_dns_cache_put(
            handle.raw,
            query.as_ptr(),
            query.len(),
            response.as_ptr(),
            response.len(),
        )
    };
    // Push the deadline into the past by storing the entry with a zero TTL cache policy is not
    // possible through the ABI; wait one second instead.
    std::thread::sleep(std::time::Duration::from_millis(1100));

    let mut payload: *mut u8 = std::ptr::null_mut();
    let mut payload_len = 0usize;
    let status = unsafe {
        diting_dns_cache_get(
            handle.raw,
            query.as_ptr(),
            query.len(),
            1,
            &mut payload,
            &mut payload_len,
        )
    };
    assert_eq!(status, GET_STALE);
    let bytes = unsafe { payload_slice(payload, payload_len) };
    assert_eq!(bytes[1], 1);
    let wire_len = u32::from_le_bytes([bytes[3], bytes[4], bytes[5], bytes[6]]) as usize;
    let wire = &bytes[7..7 + wire_len];
    assert_eq!(ttl_at(wire, "stale.example."), 1);
    unsafe { diting_dns_cache_free_bytes(payload, payload_len) };

    assert_eq!(
        unsafe { diting_dns_cache_refresh_begin(handle.raw, query.as_ptr(), query.len()) },
        1
    );
    assert_eq!(
        unsafe { diting_dns_cache_refresh_begin(handle.raw, query.as_ptr(), query.len()) },
        0
    );
    unsafe { diting_dns_cache_refresh_done(handle.raw, query.as_ptr(), query.len()) };
    assert_eq!(
        unsafe { diting_dns_cache_refresh_begin(handle.raw, query.as_ptr(), query.len()) },
        1
    );
    unsafe { diting_dns_cache_refresh_done(handle.raw, query.as_ptr(), query.len()) };
}

#[test]
fn stats_and_snapshot_reach_the_caller() {
    let handle = build(&test_config(true, false));
    let query = query_message("stats.example.", TYPE_A);
    let answers = [record("stats.example.", TYPE_A, 300, &[192, 0, 2, 9])];
    let response = answer("stats.example.", &answers);
    unsafe {
        diting_dns_cache_put(
            handle.raw,
            query.as_ptr(),
            query.len(),
            response.as_ptr(),
            response.len(),
        )
    };
    for _ in 0..2 {
        let mut payload: *mut u8 = std::ptr::null_mut();
        let mut payload_len = 0usize;
        unsafe {
            diting_dns_cache_get(
                handle.raw,
                query.as_ptr(),
                query.len(),
                1,
                &mut payload,
                &mut payload_len,
            )
        };
        unsafe { diting_dns_cache_free_bytes(payload, payload_len) };
    }

    let mut payload: *mut u8 = std::ptr::null_mut();
    let mut payload_len = 0usize;
    unsafe { diting_dns_cache_stats(handle.raw, &mut payload, &mut payload_len) };
    let bytes = unsafe { payload_slice(payload, payload_len) };
    assert_eq!(bytes[0], LAYOUT_VERSION);
    assert_eq!(bytes[1], 1); // enabled
    assert_eq!(
        u64::from_le_bytes(bytes[2..10].try_into().unwrap()),
        2,
        "two hits"
    );
    assert_eq!(
        u64::from_le_bytes(bytes[10..18].try_into().unwrap()),
        0,
        "no misses"
    );
    assert_eq!(
        u32::from_le_bytes(bytes[42..46].try_into().unwrap()),
        1,
        "one entry"
    );
    unsafe { diting_dns_cache_free_bytes(payload, payload_len) };

    unsafe { diting_dns_cache_snapshot(handle.raw, 10, &mut payload, &mut payload_len) };
    let bytes = unsafe { payload_slice(payload, payload_len) };
    assert_eq!(bytes[0], LAYOUT_VERSION);
    assert_eq!(u32::from_le_bytes(bytes[1..5].try_into().unwrap()), 1);
    assert_eq!(
        u32::from_le_bytes(bytes[5..9].try_into().unwrap()) as usize,
        b"stats.example:1:1".len()
    );
    assert_eq!(
        &bytes[9..9 + b"stats.example:1:1".len()],
        b"stats.example:1:1"
    );
    unsafe { diting_dns_cache_free_bytes(payload, payload_len) };

    unsafe { diting_dns_cache_clear(handle.raw) };
    unsafe { diting_dns_cache_stats(handle.raw, &mut payload, &mut payload_len) };
    let bytes = unsafe { payload_slice(payload, payload_len) };
    assert_eq!(u32::from_le_bytes(bytes[42..46].try_into().unwrap()), 0);
    unsafe { diting_dns_cache_free_bytes(payload, payload_len) };
}

#[test]
fn a_null_handle_is_a_no_op() {
    let query = query_message("null.example.", TYPE_A);
    let mut payload: *mut u8 = std::ptr::null_mut();
    let mut payload_len = 0usize;
    assert_eq!(
        unsafe {
            diting_dns_cache_get(
                std::ptr::null_mut(),
                query.as_ptr(),
                query.len(),
                1,
                &mut payload,
                &mut payload_len,
            )
        },
        GET_BAD_ARGS
    );
    assert_eq!(
        unsafe {
            diting_dns_cache_put(
                std::ptr::null_mut(),
                query.as_ptr(),
                query.len(),
                query.as_ptr(),
                query.len(),
            )
        },
        0
    );
    unsafe {
        diting_dns_cache_stats(std::ptr::null_mut(), &mut payload, &mut payload_len);
        diting_dns_cache_snapshot(std::ptr::null_mut(), 5, &mut payload, &mut payload_len);
        diting_dns_cache_free_bytes(payload, payload_len);
        diting_dns_cache_clear(std::ptr::null_mut());
        diting_dns_cache_close(std::ptr::null_mut());
        diting_dns_cache_refresh_done(std::ptr::null_mut(), query.as_ptr(), query.len());
        diting_dns_cache_free(std::ptr::null_mut());
    }
}

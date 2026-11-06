//! The C ABI surface: buffer contracts, payload layout and rejection codes.

use std::slice;

use super::*;
use crate::payload::{decode_response_meta, LAYOUT_VERSION};
use crate::wire::parse_response;

const CLASS_IN: u16 = 1;
const TYPE_A: u16 = 1;
const TYPE_CNAME: u16 = 5;
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

fn response(flags: u16, answers: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x2222u16.to_be_bytes());
    out.extend(flags.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend((answers.len() as u16).to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire("Query.Example."));
    out.extend(TYPE_AAAA.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    for rr in answers {
        out.extend_from_slice(rr);
    }
    out
}

unsafe fn payload_slice(pointer: *const u8, length: usize) -> &'static [u8] {
    slice::from_raw_parts(pointer, length)
}

#[test]
fn abi_is_advertised() {
    assert_eq!(diting_dns_cache_abi_version(), ABI_VERSION);
}

#[test]
fn question_key_crosses_the_boundary() {
    let wire = query_message("Example.COM.", TYPE_AAAA);
    let mut key = vec![0u8; crate::wire::MAX_KEY_LEN];
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
    let mut key = vec![0u8; 4];
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
    assert_eq!(length, LENGTH_TOO_SMALL);

    let truncated = [0u8; 8];
    let mut key = vec![0u8; crate::wire::MAX_KEY_LEN];
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
fn parse_response_payload_layout() {
    let answers = [
        record(
            "query.example.",
            TYPE_CNAME,
            300,
            &name_wire("Target.Example."),
        ),
        record("target.example.", TYPE_A, 60, &[1, 2, 3, 4]),
    ];
    let wire = response(0x8180, &answers);
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_dns_cache_parse_response(wire.as_ptr(), wire.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_OK);

    let payload = unsafe { payload_slice(out, out_len) };
    assert_eq!(payload[0], LAYOUT_VERSION);
    assert_eq!(&payload[1..3], &2u16.to_le_bytes()); // answer_count
    assert_eq!(payload[3], 0); // rcode
    assert_eq!(payload[4], 0b10); // not truncated, min TTL present
    assert_eq!(&payload[5..9], &60u32.to_le_bytes());
    assert_eq!(&payload[9..11], &2u16.to_le_bytes()); // two answer TTL offsets

    // The payload decodes back into the metadata the wire parser produced.
    let expected = parse_response(&wire).expect("valid response");
    assert_eq!(decode_response_meta(payload), Ok(expected));
    unsafe { diting_dns_cache_free_bytes(out, out_len) };
}

#[test]
fn parse_response_rejects_a_wire_it_cannot_read() {
    let short = [0u8; 11];
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len = 0usize;
    let status = unsafe {
        diting_dns_cache_parse_response(short.as_ptr(), short.len(), &mut out, &mut out_len)
    };
    assert_eq!(status, STATUS_REJECTED);
    assert_eq!(out_len, 0);

    let status = unsafe {
        diting_dns_cache_parse_response(
            short.as_ptr(),
            short.len(),
            std::ptr::null_mut(),
            &mut out_len,
        )
    };
    assert_eq!(status, STATUS_BAD_ARGS);
}

#[test]
fn patch_response_crosses_the_boundary() {
    let answers = [record("target.example.", TYPE_A, 300, &[1, 2, 3, 4])];
    let wire = response(0x8180, &answers);
    let meta = parse_response(&wire).expect("valid response");

    let mut out = vec![0u8; wire.len()];
    let length = unsafe {
        diting_dns_cache_patch_response(
            wire.as_ptr(),
            wire.len(),
            meta.answer_ttl_offsets.as_ptr(),
            meta.answer_ttl_offsets.len(),
            0xbeef,
            42,
            out.as_mut_ptr(),
            out.len(),
        )
    };
    assert_eq!(length, wire.len() as isize);
    assert_eq!(&out[0..2], &0xbeefu16.to_be_bytes());
    let start = meta.answer_ttl_offsets[0] as usize;
    assert_eq!(&out[start..start + 4], &42u32.to_be_bytes()[..]);
    // The source wire is untouched.
    assert_eq!(&wire[0..2], &0x2222u16.to_be_bytes());

    let length = unsafe {
        diting_dns_cache_patch_response(
            wire.as_ptr(),
            wire.len(),
            meta.answer_ttl_offsets.as_ptr(),
            meta.answer_ttl_offsets.len(),
            1,
            1,
            out.as_mut_ptr(),
            out.len() - 1,
        )
    };
    assert_eq!(length, LENGTH_TOO_SMALL);

    let short = [0u8; 11];
    let mut small = vec![0u8; short.len()];
    let length = unsafe {
        diting_dns_cache_patch_response(
            short.as_ptr(),
            short.len(),
            std::ptr::null(),
            0,
            1,
            1,
            small.as_mut_ptr(),
            small.len(),
        )
    };
    assert_eq!(length, LENGTH_INVALID);
}

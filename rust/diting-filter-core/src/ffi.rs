use std::ffi::c_void;
use std::slice;

use crate::index::FilterIndex;
use crate::parse::{parse_document, parse_line};
use crate::parse_payload::{decode_request, encode_parsed_lines};
use crate::payload::{decode_rules, encode_decision, encode_stats};

pub const ABI_VERSION: u32 = 2;

const STATUS_OK: u32 = 0;
const STATUS_REJECTED: u32 = 1;
const STATUS_BAD_ARGS: u32 = 2;

#[no_mangle]
pub extern "C" fn diting_filter_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_filter_build(
    input: *const u8,
    input_len: usize,
    handle_out: *mut *mut c_void,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle_out.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if input.is_null() && input_len > 0 {
        return STATUS_BAD_ARGS;
    }

    let data = if input_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input, input_len)
    };

    match decode_rules(data) {
        Ok(rules) => {
            let index = Box::new(FilterIndex::build(rules));
            let stats = encode_stats(&index);
            write_payload(stats, payload_out, payload_len);
            *handle_out = Box::into_raw(index).cast::<c_void>();
            STATUS_OK
        }
        Err(error) => {
            write_payload(error.0.into_bytes(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_filter_match(
    handle: *mut c_void,
    domain: *const u8,
    domain_len: usize,
    qtype: u16,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if domain.is_null() && domain_len > 0 {
        return STATUS_BAD_ARGS;
    }

    let index = &*handle.cast::<FilterIndex>();
    let bytes = if domain_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(domain, domain_len)
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return STATUS_BAD_ARGS;
    };

    write_payload(
        encode_decision(&index.match_domain(text, qtype)),
        payload_out,
        payload_len,
    );
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_filter_parse_rules(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    run_parse(input, input_len, payload_out, payload_len, true)
}

#[no_mangle]
pub unsafe extern "C" fn diting_filter_parse_rule(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    run_parse(input, input_len, payload_out, payload_len, false)
}

unsafe fn run_parse(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
    document: bool,
) -> u32 {
    if payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if input.is_null() && input_len > 0 {
        return STATUS_BAD_ARGS;
    }

    let data = if input_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input, input_len)
    };

    match decode_request(data) {
        Ok(text) => {
            let lines = if document {
                parse_document(&text)
            } else {
                parse_line(&text).into_iter().collect()
            };
            write_payload(encode_parsed_lines(&lines), payload_out, payload_len);
            STATUS_OK
        }
        Err(error) => {
            write_payload(error.0.into_bytes(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_filter_free(handle: *mut c_void) {
    if !handle.is_null() {
        drop(Box::from_raw(handle.cast::<FilterIndex>()));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_filter_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::payload::{NO_CODE, NO_INDEX};

    fn rule_payload() -> Vec<u8> {
        let mut out = vec![crate::payload::LAYOUT_VERSION];
        out.extend_from_slice(&1u32.to_le_bytes());
        out.push(0);
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&8u16.to_le_bytes());
        out.extend_from_slice(b"ads.test");
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes());
        out
    }

    #[test]
    fn abi_is_advertised() {
        assert_eq!(diting_filter_abi_version(), ABI_VERSION);
    }

    #[test]
    fn build_then_match_then_free() {
        let payload = rule_payload();
        let mut handle: *mut c_void = std::ptr::null_mut();
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut out_len = 0usize;
        let status = unsafe {
            diting_filter_build(
                payload.as_ptr(),
                payload.len(),
                &mut handle,
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(status, STATUS_OK);
        let stats = unsafe { payload_slice(out, out_len) };
        assert_eq!(stats[0], crate::payload::LAYOUT_VERSION);
        assert_eq!(&stats[1..5], &1u32.to_le_bytes());
        assert_eq!(stats[5], 0);
        assert_eq!(&stats[6..10], &0u32.to_le_bytes());
        unsafe { diting_filter_free_bytes(out, out_len) };

        let domain = b"ads.test";
        let status = unsafe {
            diting_filter_match(
                handle,
                domain.as_ptr(),
                domain.len(),
                1,
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(status, STATUS_OK);
        let decision = unsafe { payload_slice(out, out_len) };
        assert_eq!(decision[0], crate::payload::LAYOUT_VERSION);
        assert_eq!(decision[1], crate::index::Action::Block.code());
        assert_eq!(decision[2], crate::index::Reason::Blacklist.code());
        assert_eq!(&decision[3..7], &0u32.to_le_bytes());
        assert_eq!(decision[7], 0);
        unsafe { diting_filter_free_bytes(out, out_len) };

        unsafe { diting_filter_free(handle) };
    }

    #[test]
    fn a_pass_decision_carries_no_rule() {
        let payload = rule_payload();
        let mut handle: *mut c_void = std::ptr::null_mut();
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut out_len = 0usize;
        unsafe {
            diting_filter_build(
                payload.as_ptr(),
                payload.len(),
                &mut handle,
                &mut out,
                &mut out_len,
            );
            diting_filter_free_bytes(out, out_len);
        }

        let domain = b"clean.test";
        let status = unsafe {
            diting_filter_match(
                handle,
                domain.as_ptr(),
                domain.len(),
                1,
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(status, STATUS_OK);
        let decision = unsafe { payload_slice(out, out_len) };
        assert_eq!(decision[1], crate::index::Action::Pass.code());
        assert_eq!(decision[2], NO_CODE);
        assert_eq!(&decision[3..7], &NO_INDEX.to_le_bytes());
        unsafe {
            diting_filter_free_bytes(out, out_len);
            diting_filter_free(handle);
        }
    }

    #[test]
    fn a_malformed_payload_is_rejected_with_a_message() {
        let payload = [crate::payload::LAYOUT_VERSION, 9, 9];
        let mut handle: *mut c_void = std::ptr::null_mut();
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut out_len = 0usize;
        let status = unsafe {
            diting_filter_build(
                payload.as_ptr(),
                payload.len(),
                &mut handle,
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(status, STATUS_REJECTED);
        assert!(handle.is_null());
        let message = String::from_utf8(unsafe { payload_slice(out, out_len) }.to_vec())
            .expect("message is UTF-8");
        assert!(message.contains("truncated"), "{message}");
        unsafe { diting_filter_free_bytes(out, out_len) };
    }

    #[test]
    fn bad_arguments_are_reported() {
        let mut out: *mut u8 = std::ptr::null_mut();
        let mut out_len = 0usize;
        let mut handle: *mut c_void = std::ptr::null_mut();
        let status = unsafe {
            diting_filter_build(std::ptr::null(), 4, &mut handle, &mut out, &mut out_len)
        };
        assert_eq!(status, STATUS_BAD_ARGS);
        let status = unsafe {
            diting_filter_match(
                std::ptr::null_mut(),
                b"a.test".as_ptr(),
                6,
                1,
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(status, STATUS_BAD_ARGS);
        unsafe {
            diting_filter_free(std::ptr::null_mut());
            diting_filter_free_bytes(std::ptr::null_mut(), 0);
        }
    }

    unsafe fn payload_slice(pointer: *mut u8, length: usize) -> &'static [u8] {
        if pointer.is_null() || length == 0 {
            return &[];
        }
        slice::from_raw_parts(pointer, length)
    }
}

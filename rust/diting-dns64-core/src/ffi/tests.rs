use super::*;
use crate::payload::{encode_addresses, encode_prefixes};

fn new_engine(prefixes: &[&str]) -> *mut Engine {
    let owned: Vec<String> = prefixes.iter().map(|text| (*text).to_string()).collect();
    let payload = encode_prefixes(&owned);
    let mut handle: *mut Engine = std::ptr::null_mut();
    let status = unsafe {
        diting_dns64_new(
            1,
            payload.as_ptr(),
            payload.len(),
            &mut handle,
            std::ptr::null_mut(),
        )
    };
    assert_eq!(status, 0);
    assert!(!handle.is_null());
    handle
}

#[test]
fn abi_version_is_stable() {
    assert_eq!(diting_dns64_abi_version(), ABI_VERSION);
}

#[test]
fn info_reports_enabled_and_prefix_count() {
    let handle = new_engine(&["64:ff9b::/96", " 2001:db8::/32 "]);
    let mut enabled = 0u8;
    let mut count = 0u32;
    assert_eq!(
        unsafe { diting_dns64_info(handle, &mut enabled, &mut count) },
        0
    );
    assert_eq!(enabled, 1);
    assert_eq!(count, 2);
    unsafe { diting_dns64_free(handle) };
}

#[test]
fn embed_writes_the_sixteen_synthesized_bytes() {
    let handle = new_engine(&["64:ff9b::/96"]);
    let v4 = [192u8, 0, 2, 1];
    let mut out = [0u8; 16];
    assert_eq!(
        unsafe { diting_dns64_embed(handle, v4.as_ptr(), v4.len(), out.as_mut_ptr()) },
        0
    );
    assert_eq!(out[12..], v4);
    assert_eq!(&out[..4], &[0x00, 0x64, 0xff, 0x9b]);
    unsafe { diting_dns64_free(handle) };
}

#[test]
fn embed_rejects_a_non_four_byte_address() {
    let handle = new_engine(&["64:ff9b::/96"]);
    let v6 = [0u8; 16];
    let mut out = [0u8; 16];
    assert_eq!(
        unsafe { diting_dns64_embed(handle, v6.as_ptr(), v6.len(), out.as_mut_ptr()) },
        1
    );
    unsafe { diting_dns64_free(handle) };
}

#[test]
fn embed_net_takes_the_prefix_bytes_and_its_length() {
    let v4 = [192u8, 0, 2, 1];
    let mut prefix = [0u8; 16];
    prefix[..4].copy_from_slice(&[0x20, 0x01, 0x0d, 0xb8]);
    let mut out = [0u8; 16];
    assert_eq!(
        unsafe {
            diting_dns64_embed_net(prefix.as_ptr(), 32, v4.as_ptr(), v4.len(), out.as_mut_ptr())
        },
        0
    );
    assert_eq!(&out[..4], &[0x20, 0x01, 0x0d, 0xb8]);
    assert_eq!(&out[4..8], &v4);

    // A 40-bit prefix keeps the low byte of the address out of the first word.
    assert_eq!(
        unsafe {
            diting_dns64_embed_net(prefix.as_ptr(), 40, v4.as_ptr(), v4.len(), out.as_mut_ptr())
        },
        0
    );
    assert_eq!(&out[5..8], &v4[..3]);
    assert_eq!(out[8], 0);
    assert_eq!(out[9], v4[3]);

    // Lengths outside the RFC 6052 set are refused, as the old `default: return nil` branch did.
    assert_eq!(
        unsafe {
            diting_dns64_embed_net(prefix.as_ptr(), 36, v4.as_ptr(), v4.len(), out.as_mut_ptr())
        },
        4
    );
}

#[test]
fn synthesize_returns_the_payload_go_decodes() {
    let handle = new_engine(&["64:ff9b::/96", "2001:db8::/32"]);
    let v4 = [192u8, 0, 2, 1];
    let mut pointer: *mut u8 = std::ptr::null_mut();
    let mut length = 0usize;
    assert_eq!(
        unsafe {
            diting_dns64_synthesize(handle, v4.as_ptr(), v4.len(), &mut pointer, &mut length)
        },
        0
    );
    let payload = unsafe { std::slice::from_raw_parts(pointer, length) };
    assert_eq!(payload[0], crate::payload::LAYOUT_VERSION);
    assert_eq!(payload[1], 2);
    assert_eq!(payload.len(), 2 + 32);
    unsafe { diting_dns64_free_bytes(pointer, length) };

    // A zero-length address is an A record without IPv4: an empty result, not an error.
    let empty = [0u8; 0];
    assert_eq!(
        unsafe { diting_dns64_synthesize(handle, empty.as_ptr(), 0, &mut pointer, &mut length) },
        0
    );
    let payload = unsafe { std::slice::from_raw_parts(pointer, length) };
    assert_eq!(payload[1], 0);
    unsafe { diting_dns64_free_bytes(pointer, length) };
    unsafe { diting_dns64_free(handle) };
}

#[test]
fn excluded_and_has_valid_answer_over_the_handle() {
    let handle = new_engine(&["64:ff9b::/96"]);
    let mut excluded = 0u8;
    let loopback = {
        let mut bytes = [0u8; 16];
        bytes[15] = 1;
        bytes
    };
    assert_eq!(
        unsafe { diting_dns64_excluded(handle, loopback.as_ptr(), loopback.len(), &mut excluded) },
        0
    );
    assert_eq!(excluded, 1);

    let addresses = encode_addresses(&[&loopback]);
    let mut valid = 0u8;
    assert_eq!(
        unsafe { diting_dns64_has_valid(handle, addresses.as_ptr(), addresses.len(), &mut valid) },
        0
    );
    assert_eq!(valid, 0);

    let global = crate::addr::parse_addr("2606:4700:4700::1111").unwrap().1;
    let addresses = encode_addresses(&[&loopback, &global]);
    assert_eq!(
        unsafe { diting_dns64_has_valid(handle, addresses.as_ptr(), addresses.len(), &mut valid) },
        0
    );
    assert_eq!(valid, 1);
    unsafe { diting_dns64_free(handle) };
}

#[test]
fn a_rejected_prefix_reports_its_index_and_status() {
    let payload = encode_prefixes(&["64:ff9b::/96".to_string(), "2001:db8::/28".to_string()]);
    let mut handle: *mut Engine = std::ptr::null_mut();
    let mut index = 0u32;
    let status =
        unsafe { diting_dns64_new(1, payload.as_ptr(), payload.len(), &mut handle, &mut index) };
    assert_eq!(status, 4);
    assert_eq!(index, 1);
    assert!(handle.is_null());
}

#[test]
fn null_handles_are_bad_arguments() {
    let mut excluded = 0u8;
    let address = [1u8, 2, 3, 4];
    assert_eq!(
        unsafe {
            diting_dns64_excluded(
                std::ptr::null(),
                address.as_ptr(),
                address.len(),
                &mut excluded,
            )
        },
        1
    );
    let mut enabled = 0u8;
    let mut count = 0u32;
    assert_eq!(
        unsafe { diting_dns64_info(std::ptr::null(), &mut enabled, &mut count) },
        1
    );
    unsafe { diting_dns64_free_bytes(std::ptr::null_mut(), 0) };
    unsafe { diting_dns64_free(std::ptr::null_mut()) };
}

//! Tests through the C ABI, the way `android/engine/mitm_sniffer_native.go` drives it.

use super::*;
use crate::payload::{decode, KIND_HTTP, KIND_TLS, KIND_UNKNOWN};

/// Calls the ABI, copies the payload and frees it, exactly like the Go wrapper.
unsafe fn classify_through_abi(data: &[u8]) -> (u8, Vec<u8>) {
    let mut pointer: *mut u8 = std::ptr::null_mut();
    let mut length = 0usize;
    assert_eq!(
        diting_sniffer_classify(data.as_ptr(), data.len(), &mut pointer, &mut length),
        STATUS_OK
    );
    let payload = slice::from_raw_parts(pointer, length).to_vec();
    diting_sniffer_free_bytes(pointer, length);
    let (kind, host) = decode(&payload).expect("payload decodes");
    (kind, host.to_vec())
}

#[test]
fn abi_version_is_the_one_go_validates() {
    assert_eq!(diting_sniffer_abi_version(), ABI_VERSION);
}

#[test]
fn classifies_all_three_kinds_through_the_abi() {
    unsafe {
        assert_eq!(
            classify_through_abi(b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"),
            (KIND_HTTP, b"example.com".to_vec())
        );
        assert_eq!(
            classify_through_abi(b"not a request"),
            (KIND_UNKNOWN, Vec::new())
        );
        // A TLS gate with a body the parser cannot read: still TLS, empty host.
        assert_eq!(
            classify_through_abi(&[0x16, 0x03, 0x01, 0x00, 0x00]),
            (KIND_TLS, Vec::new())
        );
    }
}

#[test]
fn a_zero_length_peek_is_unknown() {
    unsafe {
        assert_eq!(classify_through_abi(&[]), (KIND_UNKNOWN, Vec::new()));
    }
}

#[test]
fn null_buffers_are_rejected() {
    let mut pointer: *mut u8 = std::ptr::null_mut();
    let mut length = 0usize;
    unsafe {
        assert_eq!(
            diting_sniffer_classify(std::ptr::null(), 4, &mut pointer, &mut length),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(
            diting_sniffer_classify(b"abc".as_ptr(), 3, std::ptr::null_mut(), &mut length),
            STATUS_BAD_ARGUMENT
        );
    }
}

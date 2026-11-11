//! The exported entry points.

use super::*;

fn call(payload: &[u8]) -> (u32, Vec<u8>) {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len: usize = 0;
    let status =
        unsafe { diting_config_call(payload.as_ptr(), payload.len(), &mut out, &mut out_len) };
    if status != STATUS_OK {
        return (status, Vec::new());
    }
    let body = unsafe { slice::from_raw_parts(out, out_len).to_vec() };
    unsafe { diting_config_free_bytes(out, out_len) };
    (status, body)
}

#[test]
fn abi_version_is_published() {
    assert_eq!(diting_config_abi_version(), ABI_VERSION);
}

#[test]
fn a_call_returns_the_encoded_response() {
    let mut payload = vec![crate::payload::OP_PROTOCOL];
    payload.extend_from_slice(&3u32.to_le_bytes());
    payload.extend_from_slice(b"doq");
    let (status, body) = call(&payload);
    assert_eq!(status, STATUS_OK);
    assert_eq!(body[0], 0);
    assert_eq!(&body[1..], &3i64.to_le_bytes());

    let mut payload = vec![crate::payload::OP_DOMAIN];
    payload.extend_from_slice(&1u32.to_le_bytes());
    payload.extend_from_slice(b"A");
    let (status, body) = call(&payload);
    assert_eq!(status, STATUS_OK);
    assert_eq!(&body[1..], &[1, 0, 0, 0, b'a']);
}

#[test]
fn bad_arguments_and_bad_payloads_are_status_codes() {
    let mut out_len: usize = 0;
    assert_eq!(
        unsafe { diting_config_call(std::ptr::null(), 0, std::ptr::null_mut(), &mut out_len) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(call(&[]).0, STATUS_BAD_PAYLOAD);
    assert_eq!(call(&[42]).0, STATUS_BAD_PAYLOAD);
    // Freeing a null payload is a no-op.
    unsafe { diting_config_free_bytes(std::ptr::null_mut(), 0) };
}

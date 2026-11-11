//! The C ABI surface: status codes for a broken call, and a real payload through `call`.

use super::*;
use crate::payload::{encode_request, Request};

fn call(request: &[u8]) -> (u32, Vec<u8>) {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut out_len: usize = 0;
    let status =
        unsafe { diting_proxy_call(request.as_ptr(), request.len(), &mut out, &mut out_len) };
    if out.is_null() {
        return (status, Vec::new());
    }
    let response = unsafe { std::slice::from_raw_parts(out, out_len).to_vec() };
    unsafe { diting_proxy_free_bytes(out, out_len) };
    (status, response)
}

#[test]
fn abi_version_is_published() {
    assert_eq!(diting_proxy_abi_version(), ABI_VERSION);
}

#[test]
fn bad_arguments_and_bad_payloads_are_reported() {
    let mut out_len: usize = 0;
    let mut out: *mut u8 = std::ptr::null_mut();
    assert_eq!(
        unsafe { diting_proxy_call(std::ptr::null(), 0, std::ptr::null_mut(), &mut out_len) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_proxy_call(b"x".as_ptr(), 1, &mut out, std::ptr::null_mut()) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(call(&[]), (STATUS_BAD_PAYLOAD, Vec::new()));
    assert_eq!(call(&[1, 200]), (STATUS_BAD_PAYLOAD, Vec::new()));
}

#[test]
fn a_request_goes_through_the_opcode() {
    let request = encode_request(&Request::SocksMethodReply {
        reply: vec![0x05, 0x00],
    });
    assert_eq!(call(&request), (STATUS_OK, vec![0, 0]));

    let request = encode_request(&Request::SocksUdpAssociate);
    let (status, response) = call(&request);
    assert_eq!(status, STATUS_OK);
    assert_eq!(response[0], 0);
    assert_eq!(&response[5..], &[0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
}

#[test]
fn operation_errors_stay_inside_the_envelope() {
    let request = encode_request(&Request::SocksAuthReply {
        reply: vec![0x01, 0x01],
    });
    let (status, response) = call(&request);
    assert_eq!(status, STATUS_OK);
    assert_eq!(response[0], 1);
    assert_eq!(&response[5..], b"SOCKS5 authentication failed");
}

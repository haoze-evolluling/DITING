use std::ptr;

use super::*;
use crate::payload::{encode_configure, encode_remember, LAYOUT_VERSION};

const T0: i64 = 1_700_000_000_000_000_000;

fn configure_kernel(entries: &[(i32, Vec<String>)]) -> *mut AllowlistKernel {
    let kernel = diting_allowlist_new();
    let payload = encode_configure(entries);
    let status = unsafe { diting_allowlist_configure(kernel, payload.as_ptr(), payload.len()) };
    assert_eq!(status, STATUS_OK);
    kernel
}

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_allowlist_abi_version(), 1);
}

#[test]
fn a_null_handle_allows_and_forgets() {
    assert_eq!(unsafe { diting_allowlist_has_uids(ptr::null()) }, 0);
    assert_eq!(unsafe { diting_allowlist_grant_count(ptr::null(), 1) }, 0);
    assert_eq!(
        unsafe { diting_allowlist_domain_allowed(ptr::null(), 1, b"a".as_ptr(), 1) },
        1
    );
    assert_eq!(
        unsafe {
            diting_allowlist_connection_allowed(ptr::null(), 1, [1u8, 2, 3, 4].as_ptr(), 4, T0)
        },
        1
    );
    assert_eq!(
        unsafe { diting_allowlist_configure(ptr::null(), b"x".as_ptr(), 1) },
        STATUS_OK
    );
    assert_eq!(
        unsafe { diting_allowlist_remember(ptr::null(), b"x".as_ptr(), 1, T0) },
        STATUS_OK
    );
    unsafe { diting_allowlist_free(ptr::null_mut()) };
}

#[test]
fn configure_and_probe_go_through_the_abi() {
    let kernel = configure_kernel(&[
        (10188, vec!["Example.COM.".to_string()]),
        (10200, Vec::new()),
    ]);
    assert_eq!(unsafe { diting_allowlist_has_uids(kernel) }, 1);

    let allowed = b"sub.example.com.";
    assert_eq!(
        unsafe { diting_allowlist_domain_allowed(kernel, 10188, allowed.as_ptr(), allowed.len()) },
        1
    );
    let denied = b"other.example.";
    assert_eq!(
        unsafe { diting_allowlist_domain_allowed(kernel, 10188, denied.as_ptr(), denied.len()) },
        0
    );
    let empty_set = b"example.com.";
    assert_eq!(
        unsafe {
            diting_allowlist_domain_allowed(kernel, 10200, empty_set.as_ptr(), empty_set.len())
        },
        0
    );
    // Unselected UIDs are unrestricted.
    assert_eq!(
        unsafe { diting_allowlist_domain_allowed(kernel, 99999, denied.as_ptr(), denied.len()) },
        1
    );

    unsafe { diting_allowlist_free(kernel) };
}

#[test]
fn remember_grants_through_the_abi() {
    let kernel = configure_kernel(&[(10188, vec!["example.com".to_string()])]);
    let records = vec![(vec![203u8, 0, 113, 7], 300u32)];
    let payload = encode_remember(0, "example.com.", &records);
    assert_eq!(
        unsafe { diting_allowlist_remember(kernel, payload.as_ptr(), payload.len(), T0) },
        STATUS_OK
    );
    assert_eq!(unsafe { diting_allowlist_grant_count(kernel, 10188) }, 1);

    let address = [203u8, 0, 113, 7];
    assert_eq!(
        unsafe {
            diting_allowlist_connection_allowed(kernel, 10188, address.as_ptr(), address.len(), T0)
        },
        1
    );
    assert_eq!(
        unsafe {
            diting_allowlist_connection_allowed(
                kernel,
                10188,
                address.as_ptr(),
                address.len(),
                T0 + 300 * 1_000_000_000,
            )
        },
        0
    );
    // Another UID holds no grant.
    assert_eq!(unsafe { diting_allowlist_grant_count(kernel, 10200) }, 0);

    unsafe { diting_allowlist_free(kernel) };
}

#[test]
fn a_bad_payload_is_reported() {
    let kernel = diting_allowlist_new();
    let garbage = [LAYOUT_VERSION, 1, 0, 0, 0];
    assert_eq!(
        unsafe { diting_allowlist_configure(kernel, garbage.as_ptr(), garbage.len()) },
        STATUS_BAD_PAYLOAD
    );
    assert_eq!(
        unsafe { diting_allowlist_remember(kernel, garbage.as_ptr(), garbage.len(), T0) },
        STATUS_BAD_PAYLOAD
    );
    unsafe { diting_allowlist_free(kernel) };
}

#[test]
fn invalid_utf8_in_a_domain_is_denied_not_truncated() {
    let kernel = configure_kernel(&[(1, vec!["example.com".to_string()])]);
    let invalid = [0xffu8, 0xfe];
    assert_eq!(
        unsafe { diting_allowlist_domain_allowed(kernel, 1, invalid.as_ptr(), invalid.len()) },
        0
    );
    unsafe { diting_allowlist_free(kernel) };
}

use std::ptr;

use super::*;
use crate::payload::{encode_mark, LAYOUT_VERSION};

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_connlog_abi_version(), 1);
}

#[test]
fn a_null_handle_disables_deduplication() {
    assert_eq!(
        unsafe { diting_connlog_mark(ptr::null(), b"x".as_ptr(), 1) },
        0
    );
    assert_eq!(unsafe { diting_connlog_size(ptr::null()) }, 0);
    assert_eq!(unsafe { diting_connlog_cleared(ptr::null()) }, 0);
    assert_eq!(unsafe { diting_connlog_reset(ptr::null()) }, STATUS_OK);
    unsafe { diting_connlog_free(ptr::null_mut()) };
}

#[test]
fn mark_reset_and_counters_go_through_the_abi() {
    let kernel = diting_connlog_new();
    assert!(!kernel.is_null());

    let payload = encode_mark("", "com.example.app", "1.2.3.4", 443, 6, "");
    assert_eq!(
        unsafe { diting_connlog_mark(kernel, payload.as_ptr(), payload.len()) },
        0
    );
    assert_eq!(
        unsafe { diting_connlog_mark(kernel, payload.as_ptr(), payload.len()) },
        1
    );
    assert_eq!(unsafe { diting_connlog_size(kernel) }, 1);
    assert_eq!(unsafe { diting_connlog_cleared(kernel) }, 0);

    // The blocked variant is a different key.
    let blocked = encode_mark("blk|", "com.example.app", "1.2.3.4", 443, 6, "uid_blocked");
    assert_eq!(
        unsafe { diting_connlog_mark(kernel, blocked.as_ptr(), blocked.len()) },
        0
    );
    assert_eq!(unsafe { diting_connlog_size(kernel) }, 2);

    assert_eq!(unsafe { diting_connlog_reset(kernel) }, STATUS_OK);
    assert_eq!(unsafe { diting_connlog_size(kernel) }, 0);
    assert_eq!(unsafe { diting_connlog_cleared(kernel) }, 0);

    unsafe { diting_connlog_free(kernel) };
}

#[test]
fn a_bad_payload_is_reported() {
    let kernel = diting_connlog_new();
    let garbage = [LAYOUT_VERSION, 0, 0, 0];
    assert_eq!(
        unsafe { diting_connlog_mark(kernel, garbage.as_ptr(), garbage.len()) },
        RESULT_BAD_PAYLOAD
    );
    unsafe { diting_connlog_free(kernel) };
}

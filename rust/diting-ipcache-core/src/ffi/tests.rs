use std::ptr;

use super::*;

const DOMAIN: &[u8] = b"one.example";

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_ipcache_abi_version(), 1);
}

#[test]
fn a_null_handle_misses_and_ignores_writes() {
    assert_eq!(
        unsafe { diting_ipcache_put(ptr::null(), b"a".as_ptr(), 1, b"b".as_ptr(), 1) },
        STATUS_OK
    );
    assert_eq!(unsafe { diting_ipcache_len(ptr::null()) }, 0);
    let mut out = [0u8; 32];
    assert_eq!(
        unsafe { diting_ipcache_get(ptr::null(), b"a".as_ptr(), 1, out.as_mut_ptr(), out.len()) },
        RESULT_MISS
    );
    unsafe { diting_ipcache_free(ptr::null_mut()) };
}

#[test]
fn put_get_and_len_go_through_the_abi() {
    let cache = diting_ipcache_new(4);
    assert!(!cache.is_null());

    let ip = b"203.0.113.1";
    assert_eq!(
        unsafe { diting_ipcache_put(cache, ip.as_ptr(), ip.len(), DOMAIN.as_ptr(), DOMAIN.len()) },
        STATUS_OK
    );
    assert_eq!(unsafe { diting_ipcache_len(cache) }, 1);

    let mut out = [0u8; 32];
    let length =
        unsafe { diting_ipcache_get(cache, ip.as_ptr(), ip.len(), out.as_mut_ptr(), out.len()) };
    assert_eq!(length, DOMAIN.len() as isize);
    assert_eq!(&out[..DOMAIN.len()], DOMAIN);

    let missing = b"203.0.113.2";
    assert_eq!(
        unsafe {
            diting_ipcache_get(
                cache,
                missing.as_ptr(),
                missing.len(),
                out.as_mut_ptr(),
                out.len(),
            )
        },
        RESULT_MISS
    );

    unsafe { diting_ipcache_free(cache) };
}

#[test]
fn a_small_buffer_is_reported() {
    let cache = diting_ipcache_new(4);
    let ip = b"a";
    unsafe { diting_ipcache_put(cache, ip.as_ptr(), 1, DOMAIN.as_ptr(), DOMAIN.len()) };
    let mut out = [0u8; 4];
    assert_eq!(
        unsafe { diting_ipcache_get(cache, ip.as_ptr(), 1, out.as_mut_ptr(), out.len()) },
        RESULT_TOO_SMALL
    );
    unsafe { diting_ipcache_free(cache) };
}

#[test]
fn empty_keys_are_no_ops() {
    let cache = diting_ipcache_new(4);
    assert_eq!(
        unsafe { diting_ipcache_put(cache, ptr::null(), 0, DOMAIN.as_ptr(), DOMAIN.len()) },
        STATUS_OK
    );
    assert_eq!(
        unsafe { diting_ipcache_put(cache, b"a".as_ptr(), 1, ptr::null(), 0) },
        STATUS_OK
    );
    assert_eq!(unsafe { diting_ipcache_len(cache) }, 0);

    let mut out = [0u8; 32];
    assert_eq!(
        unsafe { diting_ipcache_get(cache, ptr::null(), 0, out.as_mut_ptr(), out.len()) },
        RESULT_MISS
    );
    unsafe { diting_ipcache_free(cache) };
}

#[test]
fn invalid_utf8_is_rejected_not_truncated() {
    let cache = diting_ipcache_new(4);
    let invalid = [0xffu8, 0xfe];
    assert_eq!(
        unsafe {
            diting_ipcache_put(
                cache,
                invalid.as_ptr(),
                invalid.len(),
                DOMAIN.as_ptr(),
                DOMAIN.len(),
            )
        },
        STATUS_BAD_ARGUMENT
    );
    let mut out = [0u8; 32];
    assert_eq!(
        unsafe {
            diting_ipcache_get(
                cache,
                invalid.as_ptr(),
                invalid.len(),
                out.as_mut_ptr(),
                out.len(),
            )
        },
        RESULT_BAD_ARGUMENT
    );
    unsafe { diting_ipcache_free(cache) };
}

#[test]
fn unicode_round_trips_through_the_abi() {
    let cache = diting_ipcache_new(4);
    let ip = b"2001:db8::1";
    let domain = "名字.example".as_bytes();
    unsafe { diting_ipcache_put(cache, ip.as_ptr(), ip.len(), domain.as_ptr(), domain.len()) };
    let mut out = [0u8; 64];
    let length =
        unsafe { diting_ipcache_get(cache, ip.as_ptr(), ip.len(), out.as_mut_ptr(), out.len()) };
    assert_eq!(&out[..length as usize], domain);
    unsafe { diting_ipcache_free(cache) };
}

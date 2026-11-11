use super::*;
use crate::limiter::{Config, Normalized};
use crate::payload::{decode_info, encode_config};

fn build(config: &Config) -> *mut RateLimiter {
    let payload = encode_config(config);
    let mut handle: *mut RateLimiter = std::ptr::null_mut();
    let status = unsafe { diting_ratelimit_new(payload.as_ptr(), payload.len(), &mut handle) };
    assert_eq!(status, STATUS_OK);
    assert!(!handle.is_null());
    handle
}

fn take_payload(out: *mut u8, len: usize) -> Vec<u8> {
    assert!(!out.is_null());
    let payload = unsafe { std::slice::from_raw_parts(out, len).to_vec() };
    unsafe { diting_ratelimit_free_bytes(out, len) };
    payload
}

fn info(handle: *mut RateLimiter) -> crate::limiter::Info {
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_ratelimit_info(handle, &mut out, &mut len) },
        STATUS_OK
    );
    decode_info(&take_payload(out, len)).expect("info payload")
}

fn config() -> Config {
    Config {
        enabled: true,
        rate: 2.0,
        burst: 2,
        ipv4_prefix: 32,
        ipv6_prefix: 128,
        exempt: vec!["127.0.0.1".to_string()],
    }
}

#[test]
fn version_matches_the_header() {
    assert_eq!(diting_ratelimit_abi_version(), ABI_VERSION);
}

#[test]
fn new_allow_and_free_round_trip() {
    let handle = build(&config());
    assert_eq!(info(handle).buckets, 0);

    let address = [192, 0, 2, 1];
    let decision = unsafe { diting_ratelimit_allow(handle, address.as_ptr(), 4, 1_000, 16384) };
    assert_eq!(decision, 1);
    let decision = unsafe { diting_ratelimit_allow(handle, address.as_ptr(), 4, 1_000, 16384) };
    assert_eq!(decision, 1);
    let decision = unsafe { diting_ratelimit_allow(handle, address.as_ptr(), 4, 1_000, 16384) };
    assert_eq!(decision, 0);
    assert_eq!(info(handle).buckets, 1);

    unsafe { diting_ratelimit_free(handle) };
}

#[test]
fn zero_length_is_the_nil_address_and_always_allowed() {
    let handle = build(&config());
    assert_eq!(
        unsafe { diting_ratelimit_allow(handle, std::ptr::null(), 0, 0, 16384) },
        1
    );
    assert_eq!(info(handle).buckets, 0);
    unsafe { diting_ratelimit_free(handle) };
}

#[test]
fn an_unusable_address_width_is_reported_without_consuming_a_bucket() {
    let handle = build(&config());
    let address = [0u8; 7];
    assert_eq!(
        unsafe { diting_ratelimit_allow(handle, address.as_ptr(), 7, 0, 16384) },
        -1
    );
    assert_eq!(info(handle).buckets, 0);
    unsafe { diting_ratelimit_free(handle) };
}

#[test]
fn a_null_handle_allows_and_ignores_cleanup() {
    assert_eq!(
        unsafe { diting_ratelimit_allow(std::ptr::null(), std::ptr::null(), 0, 0, 0) },
        1
    );
    unsafe { diting_ratelimit_cleanup(std::ptr::null(), 0) };
    let mut out: *mut u8 = std::ptr::null_mut();
    let mut len: usize = 0;
    assert_eq!(
        unsafe { diting_ratelimit_info(std::ptr::null(), &mut out, &mut len) },
        STATUS_BAD_ARGUMENT
    );
}

#[test]
fn a_bad_config_payload_is_rejected() {
    let mut handle: *mut RateLimiter = std::ptr::null_mut();
    let garbage = [9u8, 9, 9];
    assert_eq!(
        unsafe { diting_ratelimit_new(garbage.as_ptr(), garbage.len(), &mut handle) },
        STATUS_BAD_ARGUMENT
    );
    assert!(handle.is_null());

    let handle = build(&config());
    assert_eq!(
        unsafe { diting_ratelimit_configure(handle, garbage.as_ptr(), garbage.len()) },
        STATUS_BAD_ARGUMENT
    );
    assert_eq!(
        unsafe { diting_ratelimit_configure(handle, std::ptr::null(), 0) },
        STATUS_BAD_ARGUMENT
    );
    // The live config survived both rejects.
    let live = info(handle);
    assert_eq!(live.config.rate, 2.0);
    unsafe { diting_ratelimit_free(handle) };
}

#[test]
fn configure_swaps_the_config_but_keeps_the_buckets() {
    let handle = build(&config());
    let address = [192, 0, 2, 2];
    assert_eq!(
        unsafe { diting_ratelimit_allow(handle, address.as_ptr(), 4, 0, 16384) },
        1
    );
    assert_eq!(info(handle).buckets, 1);

    let mut updated = config();
    updated.rate = 9.0;
    updated.burst = 7;
    updated.exempt = vec!["10.0.0.0/8".to_string()];
    let payload = encode_config(&updated);
    assert_eq!(
        unsafe { diting_ratelimit_configure(handle, payload.as_ptr(), payload.len()) },
        STATUS_OK
    );
    let live = info(handle);
    assert_eq!(live.buckets, 1);
    assert_eq!(live.config.rate, 9.0);
    assert_eq!(live.config.burst, 7);
    assert_eq!(live.exempt_nets, 1);
    assert_eq!(
        live.config,
        Normalized {
            enabled: true,
            rate: 9.0,
            burst: 7,
            ipv4_prefix: 32,
            ipv6_prefix: 128,
        }
    );
    unsafe { diting_ratelimit_free(handle) };
}

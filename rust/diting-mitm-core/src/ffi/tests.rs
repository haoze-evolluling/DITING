//! The C ABI surface: handle lifecycle, the report payload and the rejection codes.
//!
//! These tests call the exported symbols exactly like `mitm_filter_native.go` does, so a changed
//! signature or a payload field order shows up here before the Go side sees it.

use std::path::PathBuf;
use std::slice;

use super::*;
use crate::filter::{FailureReport, DEFAULT_BLACKLIST_TTL_MS};
use crate::payload::decode_report;

struct Handle(*mut Filter);

impl Handle {
    fn new() -> Self {
        Self(diting_mitm_new())
    }
}

impl Drop for Handle {
    fn drop(&mut self) {
        unsafe { diting_mitm_free(self.0) };
    }
}

/// The byte pair the Go caller passes for a string.
fn bytes(text: &str) -> (*const u8, usize) {
    (text.as_ptr(), text.len())
}

/// Copies a payload out of the library and frees it, like `copyMitmPayload` does.
unsafe fn take_payload(pointer: *mut u8, length: usize) -> Vec<u8> {
    if pointer.is_null() || length == 0 {
        return Vec::new();
    }
    let data = slice::from_raw_parts(pointer, length).to_vec();
    diting_mitm_free_bytes(pointer, length);
    data
}

unsafe fn record_failure(
    handle: *const Filter,
    host: &str,
    error: &str,
    now_ms: i64,
) -> FailureReport {
    let (host_ptr, host_len) = bytes(host);
    let (error_ptr, error_len) = bytes(error);
    let mut payload: *mut u8 = std::ptr::null_mut();
    let mut payload_len = 0usize;
    diting_mitm_record_failure(
        handle,
        host_ptr,
        host_len,
        error_ptr,
        error_len,
        now_ms,
        &mut payload,
        &mut payload_len,
    );
    decode_report(&take_payload(payload, payload_len)).expect("the report decodes")
}

unsafe fn blacklist(
    handle: *const Filter,
    host: &str,
    reason: &str,
    now_ms: i64,
) -> Option<FailureReport> {
    let (host_ptr, host_len) = bytes(host);
    let (reason_ptr, reason_len) = bytes(reason);
    let mut payload: *mut u8 = std::ptr::null_mut();
    let mut payload_len = 0usize;
    let status = diting_mitm_blacklist(
        handle,
        host_ptr,
        host_len,
        reason_ptr,
        reason_len,
        now_ms,
        &mut payload,
        &mut payload_len,
    );
    let data = take_payload(payload, payload_len);
    if status == 0 {
        assert!(data.is_empty(), "a refusal reports no payload");
        return None;
    }
    Some(decode_report(&data).expect("the report decodes"))
}

unsafe fn allows(handle: *const Filter, host: &str, now_ms: i64) -> bool {
    let (host_ptr, host_len) = bytes(host);
    diting_mitm_allows_interception(handle, host_ptr, host_len, now_ms) == 1
}

fn temp_path(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!(
        "diting-mitm-ffi-{}-{}.txt",
        std::process::id(),
        name
    ));
    let _ = std::fs::remove_file(&path);
    path
}

#[test]
fn abi_is_advertised() {
    assert_eq!(diting_mitm_abi_version(), 1);
    assert_eq!(ABI_VERSION, diting_mitm_abi_version());
}

#[test]
fn a_null_handle_is_a_no_op() {
    let null: *const Filter = std::ptr::null();
    unsafe {
        assert_eq!(diting_mitm_set_allowed_uids(null, bytes("1001").0, 4), 0);
        assert_eq!(diting_mitm_is_uid_allowed(null, 1001), 0);
        assert_eq!(diting_mitm_has_allowed_uids(null), 0);
        assert_eq!(diting_mitm_set_bypass_rules(null, bytes("x").0, 1), 0);
        assert_eq!(diting_mitm_allows_interception(null, bytes("a").0, 1, 0), 0);
        assert_eq!(diting_mitm_blacklist_count(null, 0), 0);
        assert_eq!(
            diting_mitm_load_persistent(null, bytes("/tmp/x").0, 6, 0),
            0
        );
        diting_mitm_clear(null);
        diting_mitm_remove(null, bytes("a").0, 1);
        diting_mitm_free(std::ptr::null_mut());
        diting_mitm_free_bytes(std::ptr::null_mut(), 0);

        // The failure report is still written, and says "nothing happened".
        let report = record_failure(null, "example.com", "boom", 0);
        assert!(!report.recorded);
        assert!(report.blacklist.is_none());
    }
}

#[test]
fn the_allow_list_crosses_the_boundary() {
    let filter = Handle::new();
    unsafe {
        let (csv, csv_len) = bytes("1001,1002");
        assert_eq!(diting_mitm_set_allowed_uids(filter.0, csv, csv_len), 2);
        assert_eq!(diting_mitm_is_uid_allowed(filter.0, 1001), 1);
        assert_eq!(diting_mitm_is_uid_allowed(filter.0, 1003), 0);
        assert_eq!(diting_mitm_has_allowed_uids(filter.0), 1);

        let (rules, rules_len) = bytes("# comment\nexample.com\n");
        assert_eq!(diting_mitm_set_bypass_rules(filter.0, rules, rules_len), 1);
        assert!(!allows(filter.0, "www.example.com", 0));
        assert!(allows(filter.0, "other.org", 0));
    }
}

#[test]
fn a_failure_streak_reports_what_happened() {
    let filter = Handle::new();
    let now = 1_000_000;
    unsafe {
        let first = record_failure(filter.0, " Example.COM ", "connection reset", now);
        assert!(first.recorded);
        assert!(!first.blacklisted);
        assert_eq!(first.count, 1);
        assert_eq!(first.threshold, 3);
        assert_eq!(first.host, "example.com");
        assert!(first.blacklist.is_none());

        record_failure(filter.0, "example.com", "connection reset", now + 1);
        let third = record_failure(filter.0, "example.com", "connection reset", now + 2);
        let added = third.blacklist.expect("the third failure blacklists");
        assert_eq!(added.reason, "handshake_failure (3 failures)");
        assert_eq!(added.ttl_ms, DEFAULT_BLACKLIST_TTL_MS);
        assert!(added.write_error.is_none());

        assert!(!allows(filter.0, "example.com", now + 2));
        assert_eq!(diting_mitm_blacklist_count(filter.0, now + 2), 1);

        // Past the threshold without a new entry: the flag still says "blacklisted".
        let fourth = record_failure(filter.0, "example.com", "connection reset", now + 3);
        assert!(fourth.blacklisted);
        assert!(fourth.blacklist.is_none());
    }
}

#[test]
fn blacklisting_reports_a_reason_once() {
    let filter = Handle::new();
    let now = 42;
    unsafe {
        let added = blacklist(filter.0, "Pinned.Example", "EV certificate", now).expect("added");
        assert_eq!(added.host, "pinned.example");
        assert!(!added.recorded);
        let report = added.blacklist.expect("the payload carries the entry");
        assert_eq!(report.reason, "EV certificate");
        assert_eq!(report.ttl_ms, DEFAULT_BLACKLIST_TTL_MS);

        // A live entry is not reported twice.
        assert!(blacklist(filter.0, "pinned.example", "pinning", now).is_none());
        assert_eq!(diting_mitm_blacklist_count(filter.0, now), 1);

        // An empty host is refused.
        assert!(blacklist(filter.0, "   ", "pinning", now).is_none());
    }
}

#[test]
fn a_non_utf8_host_is_never_intercepted() {
    let filter = Handle::new();
    let invalid = [0xFFu8, 0xFE];
    unsafe {
        assert_eq!(
            diting_mitm_allows_interception(filter.0, invalid.as_ptr(), invalid.len(), 0),
            0
        );
        let mut payload: *mut u8 = std::ptr::null_mut();
        let mut payload_len = 0usize;
        diting_mitm_record_failure(
            filter.0,
            invalid.as_ptr(),
            invalid.len(),
            bytes("boom").0,
            4,
            0,
            &mut payload,
            &mut payload_len,
        );
        let report = decode_report(&take_payload(payload, payload_len)).expect("decodes");
        assert!(!report.recorded);
        assert!(!report.blacklisted);
        assert_eq!(diting_mitm_blacklist_count(filter.0, 0), 0);
    }
}

#[test]
fn the_persistent_list_crosses_the_boundary() {
    let path = temp_path("boundary");
    let path_text = path.to_str().expect("the temp path is UTF-8");
    let now = 1_700_000_000_000;
    unsafe {
        let filter = Handle::new();
        let (path_ptr, path_len) = bytes(path_text);
        assert_eq!(
            diting_mitm_load_persistent(filter.0, path_ptr, path_len, now),
            0
        );

        let added = blacklist(filter.0, "example.com", "pinning", now).expect("added");
        assert!(added.blacklist.expect("entry").write_error.is_none());

        let (host, host_len) = bytes("example.com");
        diting_mitm_remove(filter.0, host, host_len);
        assert_eq!(diting_mitm_blacklist_count(filter.0, now), 0);

        // The file still holds the line: removing only forgets the in-memory entry, like the Go
        // original. A reload brings it back.
        assert_eq!(
            diting_mitm_load_persistent(filter.0, path_ptr, path_len, now + 1),
            1
        );
        assert!(!allows(filter.0, "example.com", now + 1));

        diting_mitm_clear(filter.0);
        assert_eq!(diting_mitm_blacklist_count(filter.0, now), 0);
        assert!(allows(filter.0, "example.com", now));
        assert_eq!(
            std::fs::read_to_string(&path).expect("the file is truncated"),
            ""
        );
    }
    let _ = std::fs::remove_file(&path);
}

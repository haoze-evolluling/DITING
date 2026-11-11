use std::ptr;

use super::*;
use crate::logagg::LogItem;
use crate::payload::{
    decode_log_batch, decode_traffic_tick, encode_flow_key, encode_log_push, LAYOUT_VERSION,
};
use crate::uidcache::{Addr, FlowKey};

fn item(domain: &str) -> LogItem {
    LogItem {
        domain: domain.to_string(),
        blocked: false,
        query_type: 1,
        response_time_ms: 0,
        app_name: String::new(),
        resolved_ips: String::new(),
        blocked_by: String::new(),
        error_message: String::new(),
        cached: false,
        timestamp_ms: 0,
        ttl: 0,
    }
}

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_telemetry_abi_version(), 1);
}

#[test]
fn null_handles_degrade_instead_of_failing() {
    unsafe {
        assert_eq!(
            diting_telemetry_log_push(ptr::null(), ptr::null(), 0),
            PUSH_NULL_HANDLE
        );
        assert_eq!(diting_telemetry_log_pending(ptr::null()), 0);
        assert_eq!(diting_telemetry_log_dropped(ptr::null()), 0);
        assert_eq!(diting_telemetry_log_dropped_conn(ptr::null()), 0);
        assert_eq!(
            diting_telemetry_traffic_record(ptr::null(), 1000, 1, 1),
            STATUS_BAD_ARGUMENT
        );
        assert_eq!(diting_telemetry_traffic_interval_ms(ptr::null()), 0);
        assert_eq!(
            diting_telemetry_flow_lookup(ptr::null(), ptr::null(), 0, ptr::null_mut()),
            LOOKUP_NULL_HANDLE
        );
        assert_eq!(diting_telemetry_flow_len(ptr::null()), 0);
        assert_eq!(
            diting_telemetry_package_lookup(ptr::null(), 1, 0, ptr::null_mut(), 0),
            TEXT_MISS
        );
        assert_eq!(diting_telemetry_package_len(ptr::null()), 0);
        diting_telemetry_log_free(ptr::null_mut());
        diting_telemetry_traffic_free(ptr::null_mut());
        diting_telemetry_flow_free(ptr::null_mut());
        diting_telemetry_package_free(ptr::null_mut());
        diting_telemetry_free_bytes(ptr::null_mut(), 0);
    }
}

#[test]
fn the_log_buffer_goes_through_the_abi() {
    let kernel = diting_telemetry_log_new();
    assert!(!kernel.is_null());

    let first = encode_log_push(&item("a.example"));
    let second = encode_log_push(&item("b.example"));
    unsafe {
        assert_eq!(
            diting_telemetry_log_push(kernel, first.as_ptr(), first.len()),
            PUSH_BUFFERED
        );
        assert_eq!(
            diting_telemetry_log_push(kernel, second.as_ptr(), second.len()),
            PUSH_BUFFERED
        );
        assert_eq!(diting_telemetry_log_pending(kernel), 2);

        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len = 0usize;
        assert_eq!(
            diting_telemetry_log_drain(kernel, 50, &mut out, &mut out_len),
            STATUS_OK
        );
        let batch = std::slice::from_raw_parts(out, out_len);
        let rows = decode_log_batch(batch).expect("batch payload");
        diting_telemetry_free_bytes(out, out_len);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].domain, "a.example");
        assert_eq!(rows[1].domain, "b.example");
        assert_eq!(diting_telemetry_log_pending(kernel), 0);

        // A bad payload is reported, not queued.
        let garbage = [LAYOUT_VERSION, 0, 0];
        assert_eq!(
            diting_telemetry_log_push(kernel, garbage.as_ptr(), garbage.len()),
            PUSH_BAD_PAYLOAD
        );
        diting_telemetry_log_free(kernel);
    }
}

#[test]
fn the_traffic_counters_go_through_the_abi() {
    let kernel = diting_telemetry_traffic_new();
    unsafe {
        assert_eq!(
            diting_telemetry_traffic_record(kernel, 1000, 5, 7),
            STATUS_OK
        );
        assert_eq!(diting_telemetry_traffic_record(kernel, 0, 5, 7), STATUS_OK);
        assert_eq!(diting_telemetry_traffic_unique_uids(kernel), 1);
        assert_eq!(diting_telemetry_traffic_interval_ms(kernel), 1000);
        assert_eq!(
            diting_telemetry_traffic_set_interval_ms(kernel, 10_000),
            STATUS_OK
        );
        assert_eq!(diting_telemetry_traffic_interval_ms(kernel), 10_000);

        let mut tx = 0u64;
        let mut rx = 0u64;
        assert_eq!(
            diting_telemetry_traffic_totals(kernel, 1000, &mut tx, &mut rx),
            STATUS_OK
        );
        assert_eq!((tx, rx), (5, 7));
        assert_eq!(
            diting_telemetry_traffic_totals(kernel, 2000, &mut tx, &mut rx),
            1
        );

        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len = 0usize;
        assert_eq!(
            diting_telemetry_traffic_tick(kernel, &mut out, &mut out_len),
            STATUS_OK
        );
        let payload = std::slice::from_raw_parts(out, out_len);
        let deltas = decode_traffic_tick(payload).expect("tick payload");
        diting_telemetry_free_bytes(out, out_len);
        assert_eq!(deltas.len(), 1);
        assert_eq!((deltas[0].uid, deltas[0].tx, deltas[0].rx), (1000, 5, 7));
        diting_telemetry_traffic_free(kernel);
    }
}

#[test]
fn the_flow_cache_goes_through_the_abi() {
    let kernel = diting_telemetry_flow_new();
    let key = FlowKey::new(
        Addr::V4([10, 0, 0, 2]),
        40_000,
        Addr::V4([1, 1, 1, 1]),
        443,
        6,
    );
    let lookup = encode_flow_key(&key, 0, None);
    let store = encode_flow_key(&key, 0, Some(10_123));
    unsafe {
        let mut uid = 0i32;
        assert_eq!(
            diting_telemetry_flow_lookup(kernel, lookup.as_ptr(), lookup.len(), &mut uid),
            LOOKUP_MISS
        );
        assert_eq!(
            diting_telemetry_flow_store(kernel, store.as_ptr(), store.len()),
            STATUS_OK
        );
        assert_eq!(
            diting_telemetry_flow_lookup(kernel, lookup.as_ptr(), lookup.len(), &mut uid),
            LOOKUP_HIT
        );
        assert_eq!(uid, 10_123);
        assert_eq!(diting_telemetry_flow_len(kernel), 1);

        let garbage = [LAYOUT_VERSION, 5];
        assert_eq!(
            diting_telemetry_flow_lookup(kernel, garbage.as_ptr(), garbage.len(), &mut uid),
            LOOKUP_BAD_PAYLOAD
        );
        assert_eq!(
            diting_telemetry_flow_store(kernel, garbage.as_ptr(), garbage.len()),
            STATUS_BAD_PAYLOAD
        );
        diting_telemetry_flow_free(kernel);
    }
}

#[test]
fn the_package_cache_goes_through_the_abi() {
    let kernel = diting_telemetry_package_new();
    unsafe {
        assert_eq!(
            diting_telemetry_package_store(kernel, 10_001, b"com.example".as_ptr(), 11, 0),
            STATUS_OK
        );
        assert_eq!(diting_telemetry_package_len(kernel), 1);

        let mut buffer = [0u8; 32];
        let length =
            diting_telemetry_package_lookup(kernel, 10_001, 0, buffer.as_mut_ptr(), buffer.len());
        assert_eq!(length, 11);
        assert_eq!(&buffer[..11], b"com.example");

        // Too small, then a miss.
        let mut tiny = [0u8; 4];
        assert_eq!(
            diting_telemetry_package_lookup(kernel, 10_001, 0, tiny.as_mut_ptr(), tiny.len()),
            TEXT_TOO_SMALL
        );
        assert_eq!(
            diting_telemetry_package_lookup(
                kernel,
                10_001,
                60_000_000_000,
                buffer.as_mut_ptr(),
                buffer.len()
            ),
            TEXT_MISS
        );

        // Empty names are not cached.
        assert_eq!(
            diting_telemetry_package_store(kernel, 10_002, ptr::null(), 0, 0),
            STATUS_OK
        );
        assert_eq!(diting_telemetry_package_len(kernel), 1);
        diting_telemetry_package_free(kernel);
    }
}

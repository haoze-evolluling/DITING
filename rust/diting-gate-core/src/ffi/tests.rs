//! Boundary tests: the ABI number and a round trip through the exported symbols (the Go loader
//! calls exactly these).

use super::*;
use crate::admit::{ACTION_BLOCK_QUIC, ACTION_INTERCEPT, ACTION_RELAY, FLAG_LOG_CONNECTION};

#[test]
fn abi_version_is_the_one_the_loader_validates() {
    assert_eq!(diting_gate_abi_version(), ABI_VERSION);
    assert_eq!(ABI_VERSION, 1);
}

#[test]
fn blocked_set_handle_round_trip() {
    let csv = b"10100, 10101, nope, -1";
    let handle = unsafe { diting_gate_blocked_new(csv.as_ptr(), csv.len()) };
    assert!(!handle.is_null());
    unsafe {
        assert_eq!(diting_gate_blocked_is_blocked(handle, 10100), 1);
        assert_eq!(diting_gate_blocked_is_blocked(handle, 10101), 1);
        assert_eq!(diting_gate_blocked_is_blocked(handle, 10200), 0);
        assert_eq!(diting_gate_blocked_is_blocked(handle, -1), 0);
        assert_eq!(diting_gate_blocked_is_blocked(std::ptr::null(), 10100), 0);
        diting_gate_blocked_free(handle);
    }
    assert!(unsafe { diting_gate_blocked_new(std::ptr::null(), 1) }.is_null());
}

#[test]
fn routing_symbols_round_trip() {
    let apps = b"apps";
    let all = b"all";
    let uids = [10100i64, 10101];
    unsafe {
        assert_eq!(diting_gate_per_app(1, apps.as_ptr(), apps.len()), 1);
        assert_eq!(diting_gate_per_app(0, apps.as_ptr(), apps.len()), 0);
        assert_eq!(diting_gate_per_app(1, all.as_ptr(), all.len()), 0);

        assert_eq!(
            diting_gate_proxies_uid(
                1,
                apps.as_ptr(),
                apps.len(),
                10100,
                uids.as_ptr(),
                uids.len()
            ),
            1
        );
        assert_eq!(
            diting_gate_proxies_uid(
                1,
                apps.as_ptr(),
                apps.len(),
                10200,
                uids.as_ptr(),
                uids.len()
            ),
            0
        );
        assert_eq!(
            diting_gate_proxies_uid(1, all.as_ptr(), all.len(), -1, std::ptr::null(), 0),
            1
        );

        assert_eq!(
            diting_gate_resolver_uses_proxy(1, apps.as_ptr(), apps.len()),
            0
        );
        assert_eq!(
            diting_gate_resolver_uses_proxy(1, all.as_ptr(), all.len()),
            1
        );
    }
}

#[test]
fn admit_symbol_packs_the_plan() {
    let public = [93u8, 184, 216, 34];
    let raw = unsafe {
        diting_gate_admit(
            crate::admit::MODE_FULL_UDP as u32,
            443,
            public.as_ptr(),
            public.len(),
            0,
            1,
            0,
            1, // quic_drop
            1, // quic_uid_selected
            0,
        )
    };
    let decision = crate::admit::Decision::from_u32(raw);
    assert_eq!(decision.action, ACTION_BLOCK_QUIC);
    assert!(decision.log_connection);
    assert_ne!(raw & FLAG_LOG_CONNECTION, 0);

    let raw = unsafe {
        diting_gate_admit(
            crate::admit::MODE_MITM_TCP as u32,
            443,
            public.as_ptr(),
            public.len(),
            0,
            1,
            0,
            0,
            0,
            1,
        )
    };
    assert_eq!(
        crate::admit::Decision::from_u32(raw).action,
        ACTION_INTERCEPT
    );

    let raw = unsafe {
        diting_gate_admit(
            crate::admit::MODE_FULL_TCP as u32,
            80,
            std::ptr::null(),
            0,
            0,
            1,
            0,
            0,
            0,
            0,
        )
    };
    let decision = crate::admit::Decision::from_u32(raw);
    assert_eq!(decision.action, ACTION_RELAY);
    assert!(decision.log_connection);
}

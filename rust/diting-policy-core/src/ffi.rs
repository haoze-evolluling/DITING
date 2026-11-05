//! C ABI for the policy kernel, called from the Go engine through `dlopen`/`dlsym`
//! (`android/engine/policy_native.go`).
//!
//! ```text
//! abi_version()                                   -> u32
//! snapshot_build(json, len, err, cap)             -> handle (0 = failed, err holds a message)
//! snapshot_flags(handle)                          -> u32 (bit0 hasRules, bit1 appSensitive,
//!                                                        bit2 qtypeSensitive)
//! evaluate(handle, domain, app, qtype, reason_out, reason_len) -> 0 pass / 1 block / -1 error
//! evaluate_uncached(handle, domain, app, qtype, reason_out, reason_len) -> same codes
//! prewarm(handle, previous)
//! snapshot_free(handle)
//! ```
//!
//! Contract for `evaluate`: the domain and the app name are the raw call-site values. The kernel
//! normalizes them (`normalize_domain`: lowercase, trim, no trailing dot; the app name trimmed),
//! answers from the snapshot's decision cache and only walks the tables on a miss, so Go no longer
//! keeps a cache key, an eviction policy or a normalization helper. `reason_out` receives a pointer
//! into a reason string owned by the snapshot plus its length; the caller copies it out before
//! returning, so no ownership crosses the boundary and no allocation happens per query.
//!
//! `evaluate_uncached` is the same walk and the same normalization without the cache lookup or
//! insertion. Prewarming uses it internally; the Go tests and benchmarks use it to prove a cache
//! hit never changes an answer.
//!
//! `prewarm(handle, previous)` re-evaluates the previous snapshot's hottest keys against `handle`,
//! usually on a background goroutine right after a rule reload. Both handles must stay alive for
//! the call; the kernel skips the work when either side has nothing to carry over.
//!
//! Every entry point catches panics and reports failure instead of unwinding into Go: a fault in
//! the native kernel fails the snapshot apply, which fails the engine start, never crashes the
//! tunnel.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use crate::json::RuleSnapshot;
use crate::snapshot::{Answer, Snapshot};

/// Layout/behaviour version; the Go loader refuses a library that does not speak it.
pub const ABI_VERSION: u32 = 4;

const CODE_ERROR: i32 = -1;
const CODE_PASS: i32 = 0;
const CODE_BLOCK: i32 = 1;

fn write_error(err: *mut u8, err_cap: usize, message: &str) {
    if err.is_null() || err_cap == 0 {
        return;
    }
    let bytes = message.as_bytes();
    let length = bytes.len().min(err_cap - 1);
    // SAFETY: the caller promises `err_cap` writable bytes at `err`.
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), err, length);
        *err.add(length) = 0;
    }
}

fn bytes_from<'a>(pointer: *const u8, length: usize) -> &'a [u8] {
    if pointer.is_null() || length == 0 {
        &[]
    } else {
        // SAFETY: the caller promises `length` readable bytes at `pointer` for the call.
        unsafe { slice::from_raw_parts(pointer, length) }
    }
}

/// ABI version of this artifact.
#[no_mangle]
pub extern "C" fn diting_policy_abi_version() -> u32 {
    ABI_VERSION
}

/// Builds a snapshot. Returns null on any failure (bad payload; a trie that cannot be opened does
/// not fail the build) with a message in `err`.
///
/// # Safety
/// `json` must point at `json_len` readable bytes; `err` at `err_cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn diting_policy_snapshot_build(
    json: *const u8,
    json_len: usize,
    err: *mut u8,
    err_cap: usize,
) -> *mut Snapshot {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let payload = bytes_from(json, json_len);
        let request = match RuleSnapshot::parse(payload) {
            Ok(request) => request,
            Err(error) => return Err(format!("parse rule snapshot: {error}")),
        };
        Ok(Box::into_raw(Box::new(Snapshot::build(&request))) as usize)
    }));
    match result {
        Ok(Ok(handle)) => handle as *mut Snapshot,
        Ok(Err(message)) => {
            write_error(err, err_cap, &message);
            std::ptr::null_mut()
        }
        Err(_) => {
            write_error(err, err_cap, "panic while building the policy snapshot");
            std::ptr::null_mut()
        }
    }
}

/// Snapshot flags: hasRules / appSensitive / qtypeSensitive, read once per apply so the Go side
/// can size its decision cache without a second copy of the rule tables.
///
/// # Safety
/// `handle` must be a pointer returned by [`diting_policy_snapshot_build`] and not yet freed.
#[no_mangle]
pub unsafe extern "C" fn diting_policy_snapshot_flags(handle: *const Snapshot) -> u32 {
    if handle.is_null() {
        return 0;
    }
    let snapshot = &*handle;
    catch_unwind(AssertUnwindSafe(|| snapshot.flags())).unwrap_or_default()
}

/// Shared body of [`diting_policy_evaluate`] and [`diting_policy_evaluate_uncached`].
// The argument list is the C ABI signature, not a design choice.
#[allow(clippy::too_many_arguments)]
unsafe fn evaluate_with(
    handle: *const Snapshot,
    domain: *const u8,
    domain_len: usize,
    app: *const u8,
    app_len: usize,
    qtype: u32,
    reason_out: *mut *const u8,
    reason_len: *mut usize,
    cached: bool,
) -> i32 {
    if reason_len.is_null() {
        return CODE_ERROR;
    }
    *reason_len = 0;
    if !reason_out.is_null() {
        *reason_out = std::ptr::null();
    }
    if handle.is_null() {
        return CODE_ERROR;
    }
    let snapshot = &*handle;
    let domain = bytes_from(domain, domain_len);
    let app = bytes_from(app, app_len);
    let (Ok(domain), Ok(app)) = (std::str::from_utf8(domain), std::str::from_utf8(app)) else {
        return CODE_ERROR;
    };
    let qtype = u16::try_from(qtype).unwrap_or(u16::MAX);
    let result = catch_unwind(AssertUnwindSafe(|| {
        if cached {
            snapshot.answer(domain, app, qtype)
        } else {
            snapshot.answer_uncached(domain, app, qtype)
        }
    }));
    let Ok(answer) = result else {
        return CODE_ERROR;
    };
    write_answer(answer, reason_out, reason_len)
}

/// Publishes an answer's reason: the bytes are owned by the snapshot's reason pool, so they stay
/// valid after this call returns even if the cache entry that produced them is evicted.
unsafe fn write_answer(answer: Answer, reason_out: *mut *const u8, reason_len: *mut usize) -> i32 {
    if !answer.reason.is_empty() {
        let reason = answer.reason.as_str().as_bytes();
        *reason_len = reason.len();
        if !reason_out.is_null() {
            *reason_out = reason.as_ptr();
        }
    }
    if answer.blocked {
        CODE_BLOCK
    } else {
        CODE_PASS
    }
}

/// Evaluates one query: normalizes the domain, answers from the decision cache and walks the
/// tables only on a miss.
///
/// `reason_out`/`reason_len` are only written when the answer carries a reason (a matched rule
/// pattern, or `__ALLOW__`); a plain pass reports a null pointer and zero length. The bytes stay
/// owned by the snapshot.
///
/// # Safety
/// `handle` must be alive; `domain`/`app` must point at their lengths; `reason_out` at one
/// writable `*const u8` and `reason_len` at one writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn diting_policy_evaluate(
    handle: *const Snapshot,
    domain: *const u8,
    domain_len: usize,
    app: *const u8,
    app_len: usize,
    qtype: u32,
    reason_out: *mut *const u8,
    reason_len: *mut usize,
) -> i32 {
    evaluate_with(
        handle, domain, domain_len, app, app_len, qtype, reason_out, reason_len, true,
    )
}

/// Same walk and normalization as [`diting_policy_evaluate`], but it neither reads nor fills the
/// decision cache. Used by the Go tests/benchmarks to compare against the cached path.
///
/// # Safety
/// Same contract as [`diting_policy_evaluate`].
#[no_mangle]
pub unsafe extern "C" fn diting_policy_evaluate_uncached(
    handle: *const Snapshot,
    domain: *const u8,
    domain_len: usize,
    app: *const u8,
    app_len: usize,
    qtype: u32,
    reason_out: *mut *const u8,
    reason_len: *mut usize,
) -> i32 {
    evaluate_with(
        handle, domain, domain_len, app, app_len, qtype, reason_out, reason_len, false,
    )
}

/// Re-evaluates the previous snapshot's hottest keys against `handle`. Both snapshots must stay
/// alive for the call; mismatched cache dimensions or an empty side make this a no-op.
///
/// # Safety
/// `handle` and `previous` must be pointers returned by [`diting_policy_snapshot_build`] and not
/// yet freed.
#[no_mangle]
pub unsafe extern "C" fn diting_policy_prewarm(handle: *const Snapshot, previous: *const Snapshot) {
    if handle.is_null() || previous.is_null() {
        return;
    }
    let (snapshot, previous) = (&*handle, &*previous);
    let _ = catch_unwind(AssertUnwindSafe(|| snapshot.prewarm_from(previous)));
}

/// Frees a snapshot; any mapped index stays alive while another snapshot still references it.
///
/// # Safety
/// `handle` must come from [`diting_policy_snapshot_build`] and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn diting_policy_snapshot_free(handle: *mut Snapshot) {
    if handle.is_null() {
        return;
    }
    drop(Box::from_raw(handle));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build(json: &str) -> Result<*mut Snapshot, String> {
        let mut error = [0u8; 256];
        let handle = unsafe {
            diting_policy_snapshot_build(json.as_ptr(), json.len(), error.as_mut_ptr(), error.len())
        };
        if handle.is_null() {
            let message = unsafe { std::ffi::CStr::from_ptr(error.as_ptr() as *const _) };
            return Err(message.to_string_lossy().into_owned());
        }
        Ok(handle)
    }

    fn evaluate(handle: *const Snapshot, domain: &str, app: &str, qtype: u32) -> (i32, String) {
        evaluate_code(handle, domain, app, qtype, true)
    }

    fn evaluate_uncached(
        handle: *const Snapshot,
        domain: &str,
        app: &str,
        qtype: u32,
    ) -> (i32, String) {
        evaluate_code(handle, domain, app, qtype, false)
    }

    fn evaluate_code(
        handle: *const Snapshot,
        domain: &str,
        app: &str,
        qtype: u32,
        cached: bool,
    ) -> (i32, String) {
        type EvaluateFn = unsafe extern "C" fn(
            *const Snapshot,
            *const u8,
            usize,
            *const u8,
            usize,
            u32,
            *mut *const u8,
            *mut usize,
        ) -> i32;
        let function: EvaluateFn = if cached {
            diting_policy_evaluate
        } else {
            diting_policy_evaluate_uncached
        };
        let mut reason_ptr: *const u8 = std::ptr::null();
        let mut reason_len = 0usize;
        let code = unsafe {
            function(
                handle,
                domain.as_ptr(),
                domain.len(),
                app.as_ptr(),
                app.len(),
                qtype,
                &mut reason_ptr,
                &mut reason_len,
            )
        };
        let reason = if reason_ptr.is_null() || reason_len == 0 {
            String::new()
        } else {
            // SAFETY: the snapshot owns the bytes and stays alive for the duration of the call.
            let bytes = unsafe { std::slice::from_raw_parts(reason_ptr, reason_len) };
            String::from_utf8_lossy(bytes).into_owned()
        };
        (code, reason)
    }

    #[test]
    fn build_evaluate_free_round_trip() {
        let handle = build(r#"{"globalBlock":["ads.example.com","*.tracker.net"]}"#).unwrap();
        unsafe {
            assert_eq!(diting_policy_snapshot_flags(handle) & 1, 1);
            let (code, reason) = evaluate(handle, "ads.example.com", "", 1);
            assert_eq!((code, reason.as_str()), (CODE_BLOCK, "ads.example.com"));
            let (code, reason) = evaluate(handle, "a.tracker.net", "", 1);
            assert_eq!((code, reason.as_str()), (CODE_BLOCK, "*.tracker.net"));
            assert_eq!(evaluate(handle, "other.net", "", 1).0, CODE_PASS);
            diting_policy_snapshot_free(handle);
        }
    }

    #[test]
    fn an_uncompilable_regex_is_dropped() {
        // An unbalanced group is invalid, so the rule is dropped and the rest of the snapshot is
        // still built.
        let json = r#"{"specialBlock":[{"pattern":"(?i","isRegex":true}],"globalBlock":["x.com"]}"#;
        let handle = build(json).expect("the snapshot still builds");
        unsafe {
            assert_eq!(evaluate(handle, "x.com", "", 1).0, CODE_BLOCK);
            diting_policy_snapshot_free(handle);
        }
    }

    #[test]
    fn invalid_payload_reports_an_error() {
        let error = build("not json").unwrap_err();
        assert!(error.contains("parse rule snapshot"), "{error}");
    }

    #[test]
    fn the_cached_path_matches_the_raw_walk() {
        let handle = build(
            r#"{
                "globalBlock": ["ads.example.com"],
                "appRules": {"com.a": {"block": ["t.example.com"]}},
                "specialBlock": [{"pattern": "q.example.com", "dnsType": "AAAA"}]
            }"#,
        )
        .unwrap();
        unsafe {
            // Raw input: the kernel folds case and drops the trailing dot itself.
            let cases = [
                (
                    "  Ads.Example.COM. ",
                    "",
                    1u32,
                    CODE_BLOCK,
                    "ads.example.com",
                ),
                ("t.example.com", " com.a ", 1, CODE_BLOCK, "t.example.com"),
                ("t.example.com", "com.b", 1, CODE_PASS, ""),
                ("q.example.com", "", 28, CODE_BLOCK, "q.example.com"),
                ("q.example.com", "", 1, CODE_PASS, ""),
                ("other.net", "", 1, CODE_PASS, ""),
            ];
            for (domain, app, qtype, want_code, want_reason) in cases {
                // Twice: the second answer comes from the cache and must be identical.
                for _ in 0..2 {
                    let (code, reason) = evaluate(handle, domain, app, qtype);
                    assert_eq!(code, want_code, "cached {domain:?} {app:?} {qtype}");
                    assert_eq!(reason, want_reason, "cached {domain:?} {app:?} {qtype}");
                }
                let (code, reason) = evaluate_uncached(handle, domain, app, qtype);
                assert_eq!(code, want_code, "uncached {domain:?} {app:?} {qtype}");
                assert_eq!(reason, want_reason, "uncached {domain:?} {app:?} {qtype}");
            }
            diting_policy_snapshot_free(handle);
        }
    }

    #[test]
    fn prewarm_carries_hot_keys_to_the_new_snapshot() {
        let previous = build(r#"{"globalBlock":["hot.com"]}"#).unwrap();
        unsafe {
            for _ in 0..20 {
                assert_eq!(evaluate(previous, "hot.com", "", 1).0, CODE_BLOCK);
            }
            let next = build(r#"{"globalAllow":["hot.com"],"globalBlock":["*.ads.com"]}"#).unwrap();
            diting_policy_prewarm(next, previous);
            let (code, reason) = evaluate(next, "hot.com", "", 1);
            assert_eq!((code, reason.as_str()), (CODE_PASS, "__ALLOW__"));
            assert_eq!(evaluate_uncached(next, "hot.com", "", 1).0, CODE_PASS);
            diting_policy_snapshot_free(next);
            diting_policy_snapshot_free(previous);
        }
    }
}

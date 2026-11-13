//! The runtime-log capture group: the file listing and export document, the `logcat` plan and byte
//! budget, and the `dns_cache` projection.

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use super::{answer_bytes, guarded, with_bytes, with_handle, with_handle_mut};
use crate::api;
use crate::capture::Session;
use crate::runtime_event::{Gate, Level};

/// `LogNative.storeIndex(packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_storeIndex<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::store_index));
    answer_bytes(&env, answer)
}

/// `LogNative.storeDocument(packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_storeDocument<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::store_document));
    answer_bytes(&env, answer)
}

/// `LogNative.capturePlan(pid, uid, detailed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_capturePlan<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    pid: jint,
    uid: jint,
    detailed: jint,
) -> jbyteArray {
    let answer = guarded(|| Some(api::capture_plan(pid, uid, detailed != 0)));
    answer_bytes(&env, answer)
}

/// `LogNative.captureSessionNew(): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_captureSessionNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Session::new())) as jlong)).unwrap_or(0)
}

/// `LogNative.captureSessionFree(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_captureSessionFree(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Session));
    }));
}

/// `LogNative.captureLine(handle, packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_captureLine<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |session: &Session| {
                api::capture_line(session, payload)
            })
        })?
    });
    answer_bytes(&env, answer)
}

/// `LogNative.mirrorLayout(): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_mirrorLayout<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
) -> jbyteArray {
    let answer = guarded(|| Some(api::mirror_layout()));
    answer_bytes(&env, answer)
}

/// `LogNative.mirrorRows(packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_mirrorRows<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::mirror_rows));
    answer_bytes(&env, answer)
}

// --- runtime events ---------------------------------------------------------------------------

/// `LogNative.runtimeEventNew(minLevelTag, dedupWindowMs): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    min_level_tag: jint,
    dedup_window_ms: jlong,
) -> jlong {
    let level = u8::try_from(min_level_tag)
        .ok()
        .and_then(Level::from_tag)
        .unwrap_or(Level::Info);
    guarded(|| Some(Box::into_raw(Box::new(Gate::new(level, dedup_window_ms))) as jlong))
        .unwrap_or(0)
}

/// `LogNative.runtimeEventFree(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventFree(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Gate));
    }));
}

/// `LogNative.runtimeEventSetLevel(handle, minLevelTag)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventSetLevel(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    min_level_tag: jint,
) {
    let level = u8::try_from(min_level_tag)
        .ok()
        .and_then(Level::from_tag)
        .unwrap_or(Level::Info);
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle_mut(handle, |gate: &mut Gate| gate.set_min_level(level));
    }));
}

/// `LogNative.runtimeEventLine(handle, packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventLine<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle_mut(handle, |gate: &mut Gate| {
                api::runtime_event_line(gate, payload, now_ms)
            })
        })?
    });
    answer_bytes(&env, answer)
}

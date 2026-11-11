//! The runtime-log capture group: the file listing and export document, the `logcat` plan and byte
//! budget, and the `dns_cache` projection.

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use super::{answer_bytes, guarded, with_bytes, with_handle};
use crate::api;
use crate::capture::Session;

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

/// `LogNative.capturePlan(pid): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_capturePlan<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    pid: jint,
) -> jbyteArray {
    let answer = guarded(|| Some(api::capture_plan(pid)));
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

//! The four log tables, the retention plan and the crash-buffer selection.

use jni::objects::{JByteArray, JObject};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use super::{answer_bytes, guarded, mode_from_tag, with_bytes, with_handle};
use crate::api;

// --- rows -------------------------------------------------------------------------------------

/// `LogNative.dnsBatch(stats, modeTag, packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_dnsBatch<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    stats: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        let mode = mode_from_tag(mode_tag)?;
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(stats, |stats| api::dns_batch(stats, mode, payload, now_ms))
        }?)
    });
    answer_bytes(&env, answer)
}

/// `LogNative.httpEvent(stats, modeTag, packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_httpEvent<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    stats: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        let mode = mode_from_tag(mode_tag)?;
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(stats, |stats| api::http_event(stats, mode, payload, now_ms))
        }?)
    });
    answer_bytes(&env, answer)
}

/// `LogNative.raceRow(packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_raceRow<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, |payload| api::race(payload, now_ms)));
    answer_bytes(&env, answer)
}

/// `LogNative.bootstrapRow(packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_bootstrapRow<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer =
        guarded(|| with_bytes(&mut env, &packed, |payload| api::bootstrap(payload, now_ms)));
    answer_bytes(&env, answer)
}

/// `LogNative.retentionPlan(packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_retentionPlan<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::retention_plan));
    answer_bytes(&env, answer)
}

/// `LogNative.crashSelect(packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_crashSelect<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::crash_select));
    answer_bytes(&env, answer)
}

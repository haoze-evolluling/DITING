use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject};
use jni::sys::{jboolean, jbyteArray, jint, jlong, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;

use super::{answer_bytes, guarded, with_bytes, with_handle};
use crate::api;
use crate::queue::Queue;


#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    settings_tag: jint,
) -> jlong {
    let settings = u8::try_from(settings_tag)
        .ok()
        .and_then(api::queue_settings);
    match settings {
        Some(settings) => guarded(|| Some(Box::into_raw(Box::new(Queue::new(settings))) as jlong)),
        None => None,
    }
    .unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueFree(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Queue));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueSubmit<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |queue: &Queue| {
                api::queue_submit(queue, payload, now_ms)
            })
        }?)
    });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueSubmitMany<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |queue: &Queue| {
                api::queue_submit_many(queue, payload, now_ms)
            })
        }?)
    });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueTake<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> jbyteArray {
    let answer = guarded(|| unsafe { with_handle(handle, |queue: &Queue| api::queue_take(queue)) });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueRequeue<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> jint {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |queue: &Queue| api::queue_requeue(queue, payload))
        }?)
    });
    answer.map(|overflow| overflow as jint).unwrap_or(-1)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueBackoff(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jlong {
    guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.backoff(now_ms)) }).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueResetBackoff(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |queue: &Queue| queue.reset_backoff());
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueRetryWait(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jlong {
    guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.retry_wait_ms(now_ms)) })
        .unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueInBackoff(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jboolean {
    match guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.in_backoff(now_ms)) }) {
        Some(true) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueMissingLatched(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jboolean {
    match guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.missing_latched(now_ms)) })
    {
        Some(true) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueLatchMissing(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |queue: &Queue| queue.latch_missing(now_ms));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueMarkClosed(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |queue: &Queue| queue.mark_closed());
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueIsClosed(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) -> jboolean {
    match guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.is_closed()) }) {
        Some(true) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queueClose(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) -> jint {
    guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.close() as jint) }).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_queuePendingLen(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) -> jint {
    guarded(|| unsafe { with_handle(handle, |queue: &Queue| queue.pending_len() as jint) })
        .unwrap_or(0)
}

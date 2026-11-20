use jni::objects::{JByteArray, JObject};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use super::{answer_bytes, guarded, mode_from_tag, with_bytes, with_handle};
use crate::api;


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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_dnsBatchSubmit<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    stats: jlong,
    queue: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        let mode = mode_from_tag(mode_tag)?;
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(stats, |stats: &crate::stats::Stats| {
                with_handle(queue, |queue: &crate::queue::Queue| {
                    api::dns_batch_submit(stats, queue, mode, payload, now_ms)
                })
                .flatten()
            })
            .flatten()
        })
    });
    answer_bytes(&env, answer)
}

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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_httpEvents<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    stats: jlong,
    queue: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        let mode = mode_from_tag(mode_tag)?;
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(stats, |stats: &crate::stats::Stats| {
                with_handle(queue, |queue: &crate::queue::Queue| {
                    api::http_event_batch(stats, queue, mode, payload, now_ms)
                })
                .flatten()
            })
            .flatten()
        })
    });
    answer_bytes(&env, answer)
}

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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_raceRows<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| {
            api::race_batch(payload, now_ms)
        })
    });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_bootstrapRows<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| {
            api::bootstrap_batch(payload, now_ms)
        })
    });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_raceRowsSubmit<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    queue: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(queue, |queue: &crate::queue::Queue| {
                api::race_batch_submit(queue, payload, now_ms)
            })
            .flatten()
        })
    });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_bootstrapRowsSubmit<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    queue: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(queue, |queue: &crate::queue::Queue| {
                api::bootstrap_batch_submit(queue, payload, now_ms)
            })
            .flatten()
        })
    });
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_retentionPlan<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::retention_plan));
    answer_bytes(&env, answer)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_crashSelect<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| with_bytes(&mut env, &packed, api::crash_select));
    answer_bytes(&env, answer)
}

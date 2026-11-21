use jni::objects::{JByteArray, JObject};
use jni::sys::{jint, jlong};
use jni::EnvUnowned;

use super::{answer_bytes, guarded, mode_from_tag, resolve, with_bytes, with_handle};
use crate::api;

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_dnsBatch<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    stats: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            let mode = mode_from_tag(mode_tag)?;
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(stats, |stats| api::dns_batch(stats, mode, payload, now_ms))
            })?
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_dnsBatchSubmit<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    stats: jlong,
    queue: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            let mode = mode_from_tag(mode_tag)?;
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(stats, |stats: &crate::stats::Stats| {
                    with_handle(queue, |queue: &crate::queue::Queue| {
                        api::dns_batch_submit(stats, queue, mode, payload, now_ms)
                    })
                    .flatten()
                })
                .flatten()
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_httpEvent<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    stats: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            let mode = mode_from_tag(mode_tag)?;
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(stats, |stats| api::http_event(stats, mode, payload, now_ms))
            })?
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_httpEvents<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    stats: jlong,
    queue: jlong,
    mode_tag: jint,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            let mode = mode_from_tag(mode_tag)?;
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(stats, |stats: &crate::stats::Stats| {
                    with_handle(queue, |queue: &crate::queue::Queue| {
                        api::http_event_batch(stats, queue, mode, payload, now_ms)
                    })
                    .flatten()
                })
                .flatten()
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_raceRow<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| with_bytes(env, &packed, |payload| api::race(payload, now_ms)));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_bootstrapRow<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer =
            guarded(|| with_bytes(env, &packed, |payload| api::bootstrap(payload, now_ms)));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_raceRows<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| {
                api::race_batch(payload, now_ms)
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_bootstrapRows<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| {
                api::bootstrap_batch(payload, now_ms)
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_raceRowsSubmit<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    queue: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(queue, |queue: &crate::queue::Queue| {
                    api::race_batch_submit(queue, payload, now_ms)
                })
                .flatten()
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_bootstrapRowsSubmit<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    queue: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(queue, |queue: &crate::queue::Queue| {
                    api::bootstrap_batch_submit(queue, payload, now_ms)
                })
                .flatten()
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_retentionPlan<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| with_bytes(env, &packed, api::retention_plan));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_crashSelect<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| with_bytes(env, &packed, api::crash_select));
        Ok(answer_bytes(env, answer))
    })
}

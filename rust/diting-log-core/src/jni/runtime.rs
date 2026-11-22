use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject};
use jni::sys::{jint, jlong};
use jni::EnvUnowned;

use super::{answer_bytes, guarded, resolve, with_bytes, with_handle, with_handle_mut};
use crate::api;
use crate::capture::Session;
use crate::runtime_event::{Gate, Level};

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_storeIndex<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| with_bytes(env, &packed, api::store_index));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_storeDocument<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| with_bytes(env, &packed, api::store_document));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_capturePlan<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    pid: jint,
    uid: jint,
    detailed: jint,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| Some(api::capture_plan(pid, uid, detailed != 0)));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_captureSessionNew<'a>(
    _env: EnvUnowned<'_>,
    _this: JObject<'a>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Session::new())) as jlong)).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_captureSessionFree(
    _env: EnvUnowned<'_>,
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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_captureLine<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(handle, |session: &Session| {
                    api::capture_line(session, payload)
                })
            })?
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_mirrorLayout<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| Some(api::mirror_layout()));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_mirrorRows<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| with_bytes(env, &packed, api::mirror_rows));
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventNew<'a>(
    _env: EnvUnowned<'_>,
    _this: JObject<'a>,
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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventFree(
    _env: EnvUnowned<'_>,
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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventSetLevel(
    _env: EnvUnowned<'_>,
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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_runtimeEventLine<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle_mut(handle, |gate: &mut Gate| {
                    api::runtime_event_line(gate, payload, now_ms)
                })
            })?
        });
        Ok(answer_bytes(env, answer))
    })
}

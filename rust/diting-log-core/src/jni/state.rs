use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject, JString};
use jni::sys::{jboolean, jint, jlong};
use jni::EnvUnowned;

use super::{answer_bytes, guarded, read_text, resolve, with_bytes, with_handle};
use crate::api;
use crate::attr::Attr;
use crate::health::Health;
use crate::stats::Stats;
use crate::traffic::Traffic;

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsNew(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Stats::new())) as jlong)).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsFree(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Stats));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsRequestReset(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |stats: &Stats| stats.reset_requests());
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsRateReset(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |stats: &Stats| stats.reset_rate());
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer =
            guarded(|| unsafe { with_handle(handle, |stats: &Stats| api::stats_snapshot(stats)) });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_rateTick(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
    tx: jlong,
    rx: jlong,
    now_ms: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |stats: &Stats| stats.tick_rate(tx, rx, now_ms));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_rateSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| unsafe {
            with_handle(handle, |stats: &Stats| api::rate_snapshot(stats, now_ms))
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficNew(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Traffic::new())) as jlong)).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficFree(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Traffic));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficOnTick<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(handle, |traffic: &Traffic| {
                    api::traffic_on_tick(traffic, payload)
                })
            }?)
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficTake<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| unsafe {
            with_handle(handle, |traffic: &Traffic| api::traffic_take(traffic))
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficRequeue<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> jboolean {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(handle, |traffic: &Traffic| {
                    api::traffic_requeue(traffic, payload)
                })
            })
        });
        Ok(matches!(answer, Some(Some(()))))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficBackoff(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jlong {
    guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| traffic.backoff(now_ms)) })
        .unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficResetBackoff(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |traffic: &Traffic| traffic.reset_backoff());
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficInBackoff(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jboolean {
    match guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| traffic.in_backoff(now_ms)) })
    {
        Some(true) => true,
        _ => false,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficClear(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) -> jint {
    guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| traffic.clear() as jint) })
        .unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthNew(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Health::new())) as jlong)).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthFree(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Health));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthDropped<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| {
                let (rows, reason, table) = api::health_dropped(payload)?;
                unsafe {
                    with_handle(handle, |health: &Health| {
                        api::warn_answer(health.on_dropped(rows, reason, &table, now_ms))
                    })
                }
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthOpenFailure<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    database_name: JString<'local>,
    cause: JString<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            let database = read_text(env, &database_name)?;
            let cause = read_text(env, &cause)?;
            let cause = (!cause.is_empty()).then_some(cause);
            let message = format!("unable to open {database}");
            unsafe {
                with_handle(handle, |health: &Health| {
                    api::warn_answer(health.on_open_failure(&message, cause.as_deref(), now_ms))
                })
            }
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthWarn<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    message: JString<'local>,
    cause: JString<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            let message = read_text(env, &message)?;
            let cause = read_text(env, &cause)?;
            let cause = (!cause.is_empty()).then_some(cause);
            unsafe {
                with_handle(handle, |health: &Health| {
                    api::warn_answer(health.warn(&message, cause.as_deref(), now_ms))
                })
            }
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| unsafe {
            with_handle(handle, |health: &Health| {
                api::health_snapshot(&health.snapshot())
            })
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrNew(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Attr::new())) as jlong)).unwrap_or(0)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrFree(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut Attr));
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrUidLookup<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(handle, |attr: &Attr| {
                    api::attr_uid_lookup(attr, payload, now_ms)
                })
            }?)
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrUidStore<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    uid: jint,
    now_ms: jlong,
) -> jboolean {
    resolve(&mut env, |env| {
        let answer = guarded(|| {
            with_bytes(env, &packed, |payload| unsafe {
                with_handle(handle, |attr: &Attr| {
                    api::attr_uid_store(attr, payload, uid, now_ms)
                })
            })
        });
        Ok(matches!(answer, Some(Some(()))))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrPackageLookup<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    uid: jint,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let answer = guarded(|| unsafe {
            with_handle(handle, |attr: &Attr| api::attr_package_lookup(attr, uid))
        });
        Ok(answer_bytes(env, answer))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrPackageStore<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
    uid: jint,
    name: JString<'local>,
) {
    resolve(&mut env, |env| {
        let _ = guarded(|| {
            let name = read_text(env, &name)?;
            unsafe { with_handle(handle, |attr: &Attr| attr.store_package(uid, &name)) }
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrClear(
    _env: EnvUnowned<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |attr: &Attr| attr.clear());
    }));
}

//! The stateful handles: counters and rates, traffic buckets, write health and the two
//! attribution caches.

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject, JString};
use jni::sys::{jboolean, jbyteArray, jint, jlong, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;

use super::{answer_bytes, guarded, read_text, with_bytes, with_handle};
use crate::api;
use crate::attr::Attr;
use crate::health::Health;
use crate::stats::Stats;
use crate::traffic::Traffic;

// --- counters ---------------------------------------------------------------------------------

/// `LogNative.statsNew(): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Stats::new())) as jlong)).unwrap_or(0)
}

/// `LogNative.statsFree(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsFree(
    _env: JNIEnv<'_>,
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

/// `LogNative.statsRequestReset(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsRequestReset(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |stats: &Stats| stats.reset_requests());
    }));
}

/// `LogNative.statsRateReset(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsRateReset(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |stats: &Stats| stats.reset_rate());
    }));
}

/// `LogNative.statsSnapshot(handle): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_statsSnapshot<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> jbyteArray {
    let answer =
        guarded(|| unsafe { with_handle(handle, |stats: &Stats| api::stats_snapshot(stats)) });
    answer_bytes(&env, answer)
}

/// `LogNative.rateTick(handle, tx, rx, nowMs)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_rateTick(
    _env: JNIEnv<'_>,
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

/// `LogNative.rateSnapshot(handle, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_rateSnapshot<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| unsafe {
        with_handle(handle, |stats: &Stats| api::rate_snapshot(stats, now_ms))
    });
    answer_bytes(&env, answer)
}

// --- traffic ----------------------------------------------------------------------------------

/// `LogNative.trafficNew(): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Traffic::new())) as jlong)).unwrap_or(0)
}

/// `LogNative.trafficFree(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficFree(
    _env: JNIEnv<'_>,
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

/// `LogNative.trafficOnTick(handle, packed): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficOnTick<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |traffic: &Traffic| {
                api::traffic_on_tick(traffic, payload)
            })
        }?)
    });
    answer_bytes(&env, answer)
}

/// `LogNative.trafficTake(handle): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficTake<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> jbyteArray {
    let answer =
        guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| api::traffic_take(traffic)) });
    answer_bytes(&env, answer)
}

/// `LogNative.trafficRequeue(handle, packed): Boolean`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficRequeue<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
) -> jboolean {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |traffic: &Traffic| {
                api::traffic_requeue(traffic, payload)
            })
        })
    });
    match answer {
        Some(Some(())) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

/// `LogNative.trafficBackoff(handle, nowMs): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficBackoff(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jlong {
    guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| traffic.backoff(now_ms)) })
        .unwrap_or(0)
}

/// `LogNative.trafficResetBackoff(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficResetBackoff(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |traffic: &Traffic| traffic.reset_backoff());
    }));
}

/// `LogNative.trafficInBackoff(handle, nowMs): Boolean`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficInBackoff(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
    now_ms: jlong,
) -> jboolean {
    match guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| traffic.in_backoff(now_ms)) })
    {
        Some(true) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

/// `LogNative.trafficClear(handle): Int`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_trafficClear(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) -> jint {
    guarded(|| unsafe { with_handle(handle, |traffic: &Traffic| traffic.clear() as jint) })
        .unwrap_or(0)
}

// --- write health ------------------------------------------------------------------------------

/// `LogNative.healthNew(): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Health::new())) as jlong)).unwrap_or(0)
}

/// `LogNative.healthFree(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthFree(
    _env: JNIEnv<'_>,
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

/// `LogNative.healthDropped(handle, packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthDropped<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| {
            let (rows, reason, table) = api::health_dropped(payload)?;
            unsafe {
                with_handle(handle, |health: &Health| {
                    api::warn_answer(health.on_dropped(rows, reason, &table, now_ms))
                })
            }
        })
    });
    answer_bytes(&env, answer)
}

/// `LogNative.healthOpenFailure(handle, databaseName, cause, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthOpenFailure<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    database_name: JString<'local>,
    cause: JString<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        let database = read_text(&mut env, &database_name)?;
        let cause = read_text(&mut env, &cause)?;
        let cause = (!cause.is_empty()).then_some(cause);
        let message = format!("unable to open {database}");
        unsafe {
            with_handle(handle, |health: &Health| {
                api::warn_answer(health.on_open_failure(&message, cause.as_deref(), now_ms))
            })
        }
    });
    answer_bytes(&env, answer)
}

/// `LogNative.healthWarn(handle, message, cause, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthWarn<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    message: JString<'local>,
    cause: JString<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        let message = read_text(&mut env, &message)?;
        let cause = read_text(&mut env, &cause)?;
        let cause = (!cause.is_empty()).then_some(cause);
        unsafe {
            with_handle(handle, |health: &Health| {
                api::warn_answer(health.warn(&message, cause.as_deref(), now_ms))
            })
        }
    });
    answer_bytes(&env, answer)
}

/// `LogNative.healthSnapshot(handle): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_healthSnapshot<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
) -> jbyteArray {
    let answer = guarded(|| unsafe {
        with_handle(handle, |health: &Health| {
            api::health_snapshot(&health.snapshot())
        })
    });
    answer_bytes(&env, answer)
}

// --- attribution caches ------------------------------------------------------------------------

/// `LogNative.attrNew(): Long`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrNew(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jlong {
    guarded(|| Some(Box::into_raw(Box::new(Attr::new())) as jlong)).unwrap_or(0)
}

/// `LogNative.attrFree(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrFree(
    _env: JNIEnv<'_>,
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

/// `LogNative.attrUidLookup(handle, packed, nowMs): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrUidLookup<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    now_ms: jlong,
) -> jbyteArray {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |attr: &Attr| {
                api::attr_uid_lookup(attr, payload, now_ms)
            })
        }?)
    });
    answer_bytes(&env, answer)
}

/// `LogNative.attrUidStore(handle, packed, uid, nowMs): Boolean`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrUidStore<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    packed: JByteArray<'local>,
    uid: jint,
    now_ms: jlong,
) -> jboolean {
    let answer = guarded(|| {
        with_bytes(&mut env, &packed, |payload| unsafe {
            with_handle(handle, |attr: &Attr| {
                api::attr_uid_store(attr, payload, uid, now_ms)
            })
        })
    });
    match answer {
        Some(Some(())) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

/// `LogNative.attrPackageLookup(handle, uid): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrPackageLookup<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    uid: jint,
) -> jbyteArray {
    let answer = guarded(|| unsafe {
        with_handle(handle, |attr: &Attr| api::attr_package_lookup(attr, uid))
    });
    answer_bytes(&env, answer)
}

/// `LogNative.attrPackageStore(handle, uid, name)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrPackageStore<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    handle: jlong,
    uid: jint,
    name: JString<'local>,
) {
    let _ = guarded(|| {
        let name = read_text(&mut env, &name)?;
        unsafe { with_handle(handle, |attr: &Attr| attr.store_package(uid, &name)) }
    });
}

/// `LogNative.attrClear(handle)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_log_LogNative_attrClear(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        with_handle(handle, |attr: &Attr| attr.clear());
    }));
}

//! JNI entry points for `com.haoze.diting.platform.NotificationNative`.
//!
//! Kotlin reads SharedPreferences and the counters, then asks this crate how to read them and how
//! to format the line. A null `compose` answer means no detail line, so the caller keeps only the
//! status text.

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong, jstring};
use jni::JNIEnv;

use crate::compose::Stats;

fn read(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    Some(env.get_string(value).ok()?.into())
}

fn to_jstring(env: &JNIEnv<'_>, value: String) -> jstring {
    match env.new_string(value) {
        Ok(text) => text.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// `NotificationNative.statsItems(String, boolean, boolean): String`, newline-separated.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_platform_NotificationNative_statsItems<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    raw: JString<'local>,
    has_raw: jboolean,
    legacy_speed: jboolean,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let raw = read(&mut env, &raw)?;
        Some(crate::settings::stats_items(&raw, has_raw != 0, legacy_speed != 0).join("\n"))
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

/// `NotificationNative.runningText(String, String, String): String`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_platform_NotificationNative_runningText<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    custom: JString<'local>,
    mode_default: JString<'local>,
    fallback: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let custom = read(&mut env, &custom)?;
        let mode_default = read(&mut env, &mode_default)?;
        let fallback = read(&mut env, &fallback)?;
        Some(crate::settings::running_text(
            &custom,
            &mode_default,
            &fallback,
        ))
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

/// `NotificationNative.compose(String, String, long, long, long, long, long, long, boolean,
/// long, long): String?`.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_platform_NotificationNative_compose<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    items: JString<'local>,
    labels_json: JString<'local>,
    total: jlong,
    passed: jlong,
    filtered: jlong,
    failed: jlong,
    cached: jlong,
    rewritten: jlong,
    with_speed: jboolean,
    tx_bps: jlong,
    rx_bps: jlong,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let items = read(&mut env, &items)?;
        let labels_json = read(&mut env, &labels_json)?;
        let stats = Stats {
            total,
            passed,
            filtered,
            failed,
            cached,
            rewritten,
        };
        crate::compose::compose(
            &items,
            &labels_json,
            &stats,
            with_speed != 0,
            tx_bps,
            rx_bps,
        )
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

//! JNI entry points for `com.haoze.diting.automation.EventNative`.
//!
//! Kotlin collects the live values from the running service and asks this crate for the encoded
//! envelope, so the frozen schema has exactly one implementation. A failure returns null and the
//! caller skips the broadcast instead of emitting a malformed event.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::{SystemTime, UNIX_EPOCH};

use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong, jstring};
use jni::JNIEnv;

use crate::schema;

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

fn read(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    env.get_string(value).ok().map(String::from)
}

fn read_nullable(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    read(env, value).filter(|text| !text.is_empty())
}

fn to_jstring(env: &JNIEnv<'_>, value: String) -> jstring {
    match env.new_string(value) {
        Ok(text) => text.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// `EventNative.buildStateChanged(String, boolean, boolean, boolean, long, long, String): String`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_automation_EventNative_buildStateChanged<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    work_mode: JString<'local>,
    running: jboolean,
    reclaiming: jboolean,
    persisted: jboolean,
    started_at: jlong,
    paused_until: jlong,
    error: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let work_mode = read(&mut env, &work_mode)?;
        let error = read_nullable(&mut env, &error);
        Some(
            schema::state_changed(
                &work_mode,
                running != 0,
                reclaiming != 0,
                persisted != 0,
                started_at,
                paused_until,
                error.as_deref(),
                now_ms(),
            )
            .to_string(),
        )
    }));
    match answer {
        Ok(Some(text)) => to_jstring(&env, text),
        _ => std::ptr::null_mut(),
    }
}

/// `EventNative.schemaVersion(): String`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_automation_EventNative_schemaVersion<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
) -> jstring {
    to_jstring(&env, schema::SCHEMA_VERSION.to_owned())
}

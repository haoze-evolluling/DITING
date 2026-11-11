//! The MITM entry points: `startStackMitm … setHttpLogCallback`, the stage 4b surface.
//!
//! Every one of them is a thin wrapper: the handle lookup, the `catch_unwind`, and the same "empty
//! string means the method failed" contract the Go AAR had (`StartStackMitm` returned `""` when the
//! certificate manager could not start, and Kotlin treated that as "MITM unavailable").
//!
//! The log lines Go printed (`MITM CA loaded from disk`, `MITM Filter: updated allowed UIDs`, …) go
//! to the batch-log error channel through [`Engine::log_error`], because the engine has no logcat
//! bridge; the UI's log viewer already shows that channel.

use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jstring};
use jni::JNIEnv;

use super::{answer, text, with_engine};
use crate::jni::adapters::JniHttpLog;

/// `startStackMitm(certDir)`: the CA PEM, or an empty string when the session could not start.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartStackMitm(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    cert_dir: JString<'_>,
) -> jstring {
    let cert_dir = text(&mut env, &cert_dir);
    let pem = with_engine(&mut env, handle, String::new(), |engine| {
        let (pem, messages) = engine
            .mitm_state()
            .start(&cert_dir, &engine.upstream_trust());
        for message in messages {
            engine.log_error(&message);
        }
        pem
    });
    answer(&env, Some(pem))
}

/// `stopStackMitm()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopStackMitm(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.mitm_state().stop());
}

/// `isMitmActive()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeIsMitmActive(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
) -> jboolean {
    with_engine(&mut env, handle, 0, |engine| {
        u8::from(engine.mitm_state().active())
    })
}

/// `getMitmCACert(certDir)`: the live root, or the one on disk when MITM is not running.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetMitmCaCert(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    cert_dir: JString<'_>,
) -> jstring {
    let cert_dir = text(&mut env, &cert_dir);
    let pem = with_engine(&mut env, handle, String::new(), |engine| {
        match engine.mitm_state().session() {
            Some(mitm) => mitm.ca_pem(),
            None => crate::mitm::ca_pem_from(&cert_dir),
        }
    });
    answer(&env, Some(pem))
}

/// `setMitmAllowedUIDs(csv)`: the per-app interception list.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetMitmAllowedUids(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    csv: JString<'_>,
) {
    let csv = text(&mut env, &csv);
    with_engine(&mut env, handle, (), |engine| {
        let Some(mitm) = engine.mitm_state().session() else {
            engine.log_error("MITM: SetAllowedUIDs called but stack MITM is not active");
            return;
        };
        let count = mitm.filter().set_allowed_uids_csv(&csv);
        engine.log_error(&format!("MITM Filter: updated allowed UIDs ({count} apps)"));
    });
}

/// `setHttpsBypassRules(content)`: the multi-line exclusion patterns.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetHttpsBypassRules(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    content: JString<'_>,
) {
    let content = text(&mut env, &content);
    with_engine(&mut env, handle, (), |engine| {
        let Some(mitm) = engine.mitm_state().session() else {
            engine.log_error("SetHttpsBypassRules: stack MITM not active");
            return;
        };
        let count = mitm.filter().set_bypass_rules(&content);
        engine.log_error(&format!("MITM Filter: loaded {count} HTTPS bypass rules"));
    });
}

/// `setExtraPassthroughSuffixes(content)`: the same list, from the platform channel.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetExtraPassthroughSuffixes(
    env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    content: JString<'_>,
) {
    Java_com_haoze_diting_engine_Engine_nativeSetHttpsBypassRules(env, _class, handle, content);
}

/// `clearMitmBlacklist()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeClearMitmBlacklist(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
) {
    with_engine(&mut env, handle, (), |engine| {
        if let Some(mitm) = engine.mitm_state().session() {
            mitm.filter().clear_blacklist();
            engine.log_error("MITM Filter: cleared auto-blacklist");
        }
    });
}

/// `setCosmeticRules(json)`: the scoped cosmetic rule set.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetCosmeticRules(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    payload: JString<'_>,
) {
    let payload = text(&mut env, &payload);
    with_engine(&mut env, handle, (), |engine| {
        let bytes = payload.len();
        engine.mitm_state().settings().set_cosmetic_rules(&payload);
        engine.log_error(&format!("Cosmetic rules updated: {bytes} bytes"));
    });
}

/// `setRequestRules(json)`: the URL prefix rules the relay applies per request.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetRequestRules(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    payload: JString<'_>,
) {
    let payload = text(&mut env, &payload);
    with_engine(&mut env, handle, (), |engine| {
        if let Err(error) = engine.mitm_state().settings().set_request_rules(&payload) {
            engine.log_error(&error);
        }
    });
}

/// `setHttpLogCallback(cb)`; a null stops reporting.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetHttpLogCallback(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    callback: JObject<'_>,
) {
    let Some(instance) = super::lookup_checked(&mut env, handle) else {
        return;
    };
    if callback.is_null() {
        instance.engine.mitm_state().settings().set_http_log(None);
        return;
    }
    match JniHttpLog::new(&mut env, &callback) {
        Ok(sink) => instance
            .engine
            .mitm_state()
            .settings()
            .set_http_log(Some(std::sync::Arc::new(sink))),
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "setHttpLogCallback: the callback could not be captured",
            );
        }
    }
}

/// `mitmBlacklistCount()`: for the settings screen (live entries only).
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeMitmBlacklistCount(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
) -> jni::sys::jlong {
    with_engine(
        &mut env,
        handle,
        0 as jni::sys::jlong,
        |engine| match engine.mitm_state().session() {
            Some(mitm) => mitm.filter().blacklist_count(crate::mitm::now_ms()) as i64,
            None => 0,
        },
    )
}

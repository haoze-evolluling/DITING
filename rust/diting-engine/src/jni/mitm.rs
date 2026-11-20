use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jstring};
use jni::JNIEnv;

use super::{answer, text, with_engine};
use crate::jni::adapters::JniHttpLog;

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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopStackMitm(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.mitm_state().stop());
}

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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetExtraPassthroughSuffixes(
    env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jni::sys::jlong,
    content: JString<'_>,
) {
    Java_com_haoze_diting_engine_Engine_nativeSetHttpsBypassRules(env, _class, handle, content);
}

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

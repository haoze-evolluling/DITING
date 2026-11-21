use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong};
use jni::EnvUnowned;

use super::{answer, resolve, text, with_engine};
use crate::jni::adapters::JniHttpLog;

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartStackMitm<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    cert_dir: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let cert_dir = text(env, &cert_dir);
        let pem = with_engine(env, handle, String::new(), |engine| {
            let (pem, messages) = engine
                .mitm_state()
                .start(&cert_dir, &engine.upstream_trust());
            for message in messages {
                engine.log_error(&message);
            }
            pem
        });
        Ok(answer(env, Some(pem)))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopStackMitm<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.mitm_state().stop());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeIsMitmActive<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> jboolean {
    resolve(&mut env, |env| {
        Ok(with_engine(env, handle, false, |engine| {
            engine.mitm_state().active()
        }))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetMitmCaCert<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    cert_dir: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let cert_dir = text(env, &cert_dir);
        let pem = with_engine(env, handle, String::new(), |engine| {
            match engine.mitm_state().session() {
                Some(mitm) => mitm.ca_pem(),
                None => crate::mitm::ca_pem_from(&cert_dir),
            }
        });
        Ok(answer(env, Some(pem)))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetMitmAllowedUids<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    csv: JString<'local>,
) {
    resolve(&mut env, |env| {
        let csv = text(env, &csv);
        with_engine(env, handle, (), |engine| {
            let Some(mitm) = engine.mitm_state().session() else {
                engine.log_error("MITM: SetAllowedUIDs called but stack MITM is not active");
                return;
            };
            let count = mitm.filter().set_allowed_uids_csv(&csv);
            engine.log_error(&format!("MITM Filter: updated allowed UIDs ({count} apps)"));
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetHttpsBypassRules<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    content: JString<'local>,
) {
    resolve(&mut env, |env| {
        let content = text(env, &content);
        with_engine(env, handle, (), |engine| {
            let Some(mitm) = engine.mitm_state().session() else {
                engine.log_error("SetHttpsBypassRules: stack MITM not active");
                return;
            };
            let count = mitm.filter().set_bypass_rules(&content);
            engine.log_error(&format!("MITM Filter: loaded {count} HTTPS bypass rules"));
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetExtraPassthroughSuffixes<
    'local,
>(
    env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    content: JString<'local>,
) {
    Java_com_haoze_diting_engine_Engine_nativeSetHttpsBypassRules(env, _class, handle, content);
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeClearMitmBlacklist<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| {
            if let Some(mitm) = engine.mitm_state().session() {
                mitm.filter().clear_blacklist();
                engine.log_error("MITM Filter: cleared auto-blacklist");
            }
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetCosmeticRules<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JString<'local>,
) {
    resolve(&mut env, |env| {
        let payload = text(env, &payload);
        with_engine(env, handle, (), |engine| {
            let bytes = payload.len();
            engine.mitm_state().settings().set_cosmetic_rules(&payload);
            engine.log_error(&format!("Cosmetic rules updated: {bytes} bytes"));
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetRequestRules<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JString<'local>,
) {
    resolve(&mut env, |env| {
        let payload = text(env, &payload);
        with_engine(env, handle, (), |engine| {
            if let Err(error) = engine.mitm_state().settings().set_request_rules(&payload) {
                engine.log_error(&error);
            }
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetHttpLogCallback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        let Some(instance) = super::lookup_checked(env, handle) else {
            return Ok(());
        };
        if callback.is_null() {
            instance.engine.mitm_state().settings().set_http_log(None);
            return Ok(());
        }
        match JniHttpLog::new(env, &callback) {
            Ok(sink) => instance
                .engine
                .mitm_state()
                .settings()
                .set_http_log(Some(std::sync::Arc::new(sink))),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!("setHttpLogCallback: the callback could not be captured"),
                );
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeMitmBlacklistCount<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> jlong {
    resolve(&mut env, |env| {
        Ok(with_engine(env, handle, 0, |engine| {
            match engine.mitm_state().session() {
                Some(mitm) => mitm.filter().blacklist_count(crate::mitm::now_ms()) as i64,
                None => 0,
            }
        }))
    })
}

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JObject, JString};
use jni::sys::jstring;
use jni::JNIEnv;

fn read(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    Some(env.get_string(value).ok()?.into())
}

fn to_jstring(env: &JNIEnv<'_>, value: String) -> jstring {
    match env.new_string(value) {
        Ok(text) => text.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_normalizeProtocol<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    value: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text = read(&mut env, &value)?;
        Some(crate::config::protocol_or_default(&text).to_string())
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_normalizeScope<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    value: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text = read(&mut env, &value)?;
        Some(crate::config::scope_or_default(&text).to_string())
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_normalizeTargets<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    value: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text = read(&mut env, &value)?;
        Some(crate::config::filter_targets(&text))
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_packages<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    proxy_json: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text = read(&mut env, &proxy_json)?;
        Some(crate::config::packages_of(&text))
    }));
    match answer {
        Ok(Some(Some(value))) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_applyUids<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    proxy_json: JString<'local>,
    uids_csv: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let proxy_json = read(&mut env, &proxy_json)?;
        let uids_csv = read(&mut env, &uids_csv)?;
        Some(
            crate::config::apply_uids(&proxy_json, &uids_csv).unwrap_or_else(|| proxy_json.clone()),
        )
    }));
    match answer {
        Ok(Some(value)) => to_jstring(&env, value),
        _ => std::ptr::null_mut(),
    }
}

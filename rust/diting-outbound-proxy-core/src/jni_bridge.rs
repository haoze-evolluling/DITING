use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JObject, JString};
use jni::{Env, EnvUnowned};

fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

fn read(env: &mut Env<'_>, value: &JString<'_>) -> Option<String> {
    value.try_to_string(env).ok()
}

fn answer_string<'local>(env: &mut Env<'local>, value: String) -> JObject<'local> {
    match env.new_string(value) {
        Ok(text) => JObject::from(text),
        Err(_) => JObject::null(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_normalizeProtocol<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    value: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(text) = read(env, &value) else {
            return Ok(JObject::null());
        };
        Ok(answer_string(
            env,
            crate::config::protocol_or_default(&text).to_string(),
        ))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_normalizeScope<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    value: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(text) = read(env, &value) else {
            return Ok(JObject::null());
        };
        Ok(answer_string(
            env,
            crate::config::scope_or_default(&text).to_string(),
        ))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_normalizeTargets<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    value: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(text) = read(env, &value) else {
            return Ok(JObject::null());
        };
        Ok(answer_string(env, crate::config::filter_targets(&text)))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_packages<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    proxy_json: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(text) = read(env, &proxy_json) else {
            return Ok(JObject::null());
        };
        match crate::config::packages_of(&text) {
            Some(value) => Ok(answer_string(env, value)),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_proxy_OutboundProxyNative_applyUids<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    proxy_json: JString<'local>,
    uids_csv: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let (Some(proxy_json), Some(uids_csv)) = (read(env, &proxy_json), read(env, &uids_csv))
        else {
            return Ok(JObject::null());
        };
        let value =
            crate::config::apply_uids(&proxy_json, &uids_csv).unwrap_or_else(|| proxy_json.clone());
        Ok(answer_string(env, value))
    })
}

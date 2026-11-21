use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong};
use jni::{Env, EnvUnowned};

use crate::compose::Stats;

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
pub extern "system" fn Java_com_haoze_diting_platform_NotificationNative_statsItems<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    raw: JString<'local>,
    has_raw: jboolean,
    legacy_speed: jboolean,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(raw) = read(env, &raw) else {
            return Ok(JObject::null());
        };
        let items = crate::settings::stats_items(&raw, has_raw, legacy_speed);
        Ok(answer_string(env, items.join("\n")))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_platform_NotificationNative_runningText<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    custom: JString<'local>,
    mode_default: JString<'local>,
    fallback: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let (Some(custom), Some(mode_default), Some(fallback)) = (
            read(env, &custom),
            read(env, &mode_default),
            read(env, &fallback),
        ) else {
            return Ok(JObject::null());
        };
        let text = crate::settings::running_text(&custom, &mode_default, &fallback);
        Ok(answer_string(env, text))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_platform_NotificationNative_compose<'local>(
    mut env: EnvUnowned<'local>,
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
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let (Some(items), Some(labels_json)) = (read(env, &items), read(env, &labels_json)) else {
            return Ok(JObject::null());
        };
        let stats = Stats {
            total,
            passed,
            filtered,
            failed,
            cached,
            rewritten,
        };
        match crate::compose::compose(&items, &labels_json, &stats, with_speed, tx_bps, rx_bps) {
            Some(text) => Ok(answer_string(env, text)),
            None => Ok(JObject::null()),
        }
    })
}

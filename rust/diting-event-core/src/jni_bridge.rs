use std::time::{SystemTime, UNIX_EPOCH};

use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong};
use jni::{Env, EnvUnowned};

use crate::schema;

fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

fn read(env: &mut Env<'_>, value: &JString<'_>) -> Option<String> {
    value.try_to_string(env).ok()
}

fn read_nullable(env: &mut Env<'_>, value: &JString<'_>) -> Option<String> {
    read(env, value).filter(|text| !text.is_empty())
}

fn answer_string<'local>(env: &mut Env<'local>, value: String) -> JObject<'local> {
    match env.new_string(value) {
        Ok(text) => JObject::from(text),
        Err(_) => JObject::null(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_automation_EventNative_buildStateChanged<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    work_mode: JString<'local>,
    running: jboolean,
    reclaiming: jboolean,
    persisted: jboolean,
    started_at: jlong,
    paused_until: jlong,
    error: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(work_mode) = read(env, &work_mode) else {
            return Ok(JObject::null());
        };
        let error = read_nullable(env, &error);
        let document = schema::state_changed(
            &work_mode,
            running,
            reclaiming,
            persisted,
            started_at,
            paused_until,
            error.as_deref(),
            now_ms(),
        );
        Ok(answer_string(env, document.to_string()))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_automation_EventNative_schemaVersion<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        Ok(answer_string(env, schema::SCHEMA_VERSION.to_owned()))
    })
}

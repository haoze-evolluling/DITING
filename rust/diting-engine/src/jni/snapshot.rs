use jni::objects::{JByteArray, JObject};
use jni::sys::jlong;
use jni::{Env, EnvUnowned};

use super::{answer, resolve, with_engine};

fn answer_bytes<'local>(env: &mut Env<'local>, value: Option<Vec<u8>>) -> JObject<'local> {
    match value.and_then(|bytes| env.byte_array_from_slice(&bytes).ok()) {
        Some(array) => JObject::from(array),
        None => JObject::null(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStatsSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = with_engine(env, handle, None, |engine| {
            Some(crate::stats::engine_stats_snapshot(engine))
        });
        Ok(answer_bytes(env, payload))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetDnsCacheSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    limit: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = with_engine(env, handle, None, |engine| -> Option<Vec<u8>> {
            if limit <= 0 {
                return Some(crate::cache::entries_packed(&[]));
            }
            let entries = engine.cache().snapshot(limit.min(u32::MAX as i64) as u32);
            Some(crate::cache::entries_packed(&entries))
        });
        Ok(answer_bytes(env, payload))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeApplyRuleSnapshotBytes<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = match env.convert_byte_array(&payload) {
            Ok(bytes) => match String::from_utf8(bytes) {
                Ok(text) => text,
                Err(_) => {
                    return Ok(answer(
                        env,
                        Some("applyRuleSnapshot: payload is not valid UTF-8".to_string()),
                    ))
                }
            },
            Err(_) => {
                return Ok(answer(
                    env,
                    Some("applyRuleSnapshot: payload could not be read".to_string()),
                ))
            }
        };
        let answer_text = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            Some(engine.apply_rule_snapshot(&payload))
        });
        Ok(answer(env, answer_text))
    })
}

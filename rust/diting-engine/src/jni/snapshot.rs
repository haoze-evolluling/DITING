use jni::objects::{JByteArray, JObject};
use jni::sys::{jbyteArray, jlong, jstring};
use jni::JNIEnv;

use super::{answer, with_engine};

fn answer_bytes(env: &JNIEnv<'_>, value: Option<Vec<u8>>) -> jbyteArray {
    match value.and_then(|bytes| env.byte_array_from_slice(&bytes).ok()) {
        Some(array) => array.into_raw(),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStatsSnapshot<'local>(
    mut env: JNIEnv<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> jbyteArray {
    let payload = with_engine(&mut env, handle, None, |engine| {
        Some(crate::stats::engine_stats_snapshot(engine))
    });
    answer_bytes(&env, payload)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetDnsCacheSnapshot<'local>(
    mut env: JNIEnv<'local>,
    _class: JObject<'local>,
    handle: jlong,
    limit: jlong,
) -> jbyteArray {
    let payload = with_engine(&mut env, handle, None, |engine| -> Option<Vec<u8>> {
        if limit <= 0 {
            return Some(crate::cache::entries_packed(&[]));
        }
        let entries = engine.cache().snapshot(limit.min(u32::MAX as i64) as u32);
        Some(crate::cache::entries_packed(&entries))
    });
    answer_bytes(&env, payload)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeApplyRuleSnapshotBytes<'local>(
    mut env: JNIEnv<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JByteArray<'local>,
) -> jstring {
    let payload = match env.convert_byte_array(&payload) {
        Ok(bytes) => match String::from_utf8(bytes) {
            Ok(text) => text,
            Err(_) => {
                return answer(
                    &env,
                    Some("applyRuleSnapshot: payload is not valid UTF-8".to_string()),
                )
            }
        },
        Err(_) => {
            return answer(
                &env,
                Some("applyRuleSnapshot: payload could not be read".to_string()),
            )
        }
    };
    let answer_text = with_engine(
        &mut env,
        handle,
        Some("engine released".to_string()),
        |engine| Some(engine.apply_rule_snapshot(&payload)),
    );
    answer(&env, answer_text)
}

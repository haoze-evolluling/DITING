use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JByteArray, JObject, JString};
use jni::sys::jint;
use jni::{Env, EnvUnowned};

use crate::row::LogMode;

pub mod queue;
pub mod rows;
pub mod runtime;
pub mod state;

pub(super) fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

pub(super) fn with_bytes<R>(
    env: &Env<'_>,
    packed: &JByteArray<'_>,
    run: impl FnOnce(&[u8]) -> Option<R>,
) -> Option<R> {
    let payload = env.convert_byte_array(packed).ok()?;
    run(&payload)
}

pub(super) unsafe fn with_handle<T, R>(handle: i64, run: impl FnOnce(&T) -> R) -> Option<R> {
    if handle == 0 {
        return None;
    }
    Some(run(&*(handle as *const T)))
}

pub(super) unsafe fn with_handle_mut<T, R>(
    handle: i64,
    run: impl FnOnce(&mut T) -> R,
) -> Option<R> {
    if handle == 0 {
        return None;
    }
    Some(run(&mut *(handle as *mut T)))
}

pub(super) fn answer_bytes<'local>(
    env: &mut Env<'local>,
    value: Option<Vec<u8>>,
) -> JObject<'local> {
    match value.and_then(|bytes| env.byte_array_from_slice(&bytes).ok()) {
        Some(array) => JObject::from(array),
        None => JObject::null(),
    }
}

pub(super) fn mode_from_tag(tag: jint) -> Option<LogMode> {
    LogMode::from_tag(u8::try_from(tag).ok()?)
}

pub(super) fn read_text(env: &mut Env<'_>, value: &JString<'_>) -> Option<String> {
    value.try_to_string(env).ok()
}

pub(super) fn guarded<T>(value: impl FnOnce() -> Option<T>) -> Option<T> {
    catch_unwind(AssertUnwindSafe(value)).ok().flatten()
}

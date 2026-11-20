use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JString};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use crate::row::LogMode;

pub mod queue;
pub mod rows;
pub mod runtime;
pub mod state;

fn with_bytes<R>(
    env: &mut JNIEnv<'_>,
    packed: &JByteArray<'_>,
    run: impl FnOnce(&[u8]) -> Option<R>,
) -> Option<R> {
    let payload = env.convert_byte_array(packed).ok()?;
    run(&payload)
}

pub(super) unsafe fn with_handle<T, R>(handle: jlong, run: impl FnOnce(&T) -> R) -> Option<R> {
    if handle == 0 {
        return None;
    }
    Some(run(&*(handle as *const T)))
}

pub(super) unsafe fn with_handle_mut<T, R>(
    handle: jlong,
    run: impl FnOnce(&mut T) -> R,
) -> Option<R> {
    if handle == 0 {
        return None;
    }
    Some(run(&mut *(handle as *mut T)))
}

fn answer_bytes(env: &JNIEnv<'_>, value: Option<Vec<u8>>) -> jbyteArray {
    match value.and_then(|bytes| env.byte_array_from_slice(&bytes).ok()) {
        Some(array) => array.into_raw(),
        None => std::ptr::null_mut(),
    }
}

fn mode_from_tag(tag: jint) -> Option<LogMode> {
    LogMode::from_tag(u8::try_from(tag).ok()?)
}

fn read_text(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    Some(env.get_string(value).ok()?.into())
}

fn guarded<T>(value: impl FnOnce() -> Option<T>) -> Option<T> {
    catch_unwind(AssertUnwindSafe(value)).ok().flatten()
}

//! JNI entry points for the Kotlin log layer (`com.haoze.diting.log.LogNative`).
//!
//! Every request is one `ByteArray` (or a few scalars) and every answer is one `ByteArray`; the
//! layouts live in [`crate::api`]. A null answer means "the kernel could not decode this call" — a
//! missing library, a payload from a newer Kotlin side, or a panic — and `LogNative.kt` turns that
//! into an `IllegalStateException` instead of guessing.
//!
//! The stateful pieces (`Stats`, `Traffic`, `Health`, `Attr`, `Queue`) are boxed pointers handed to
//! Kotlin as `jlong` handles. Kotlin owns exactly one handle per object and frees it where the old
//! singleton died (or never, for the process-wide counters), so a handle is never shared.
//!
//! The entry points are grouped by the Kotlin class they serve: [`rows`] the four log tables and
//! the retention/crash calls, [`queue`] the writer queues, [`state`] the counters, buckets, write
//! health and attribution caches, and [`runtime`] the runtime-log capture, its files and the
//! `dns_cache` projection.

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JString};
use jni::sys::{jbyteArray, jint, jlong};
use jni::JNIEnv;

use crate::row::LogMode;

pub mod queue;
pub mod rows;
pub mod runtime;
pub mod state;

/// Runs `run` with the decoded payload; None on a failed decode (the answer becomes null).
fn with_bytes<R>(
    env: &mut JNIEnv<'_>,
    packed: &JByteArray<'_>,
    run: impl FnOnce(&[u8]) -> Option<R>,
) -> Option<R> {
    let payload = env.convert_byte_array(packed).ok()?;
    run(&payload)
}

/// Runs `run` with the handle's target; None for a null handle.
///
/// # Safety
///
/// The handle must come from the matching `*_new` and must not have been freed.
pub(super) unsafe fn with_handle<T, R>(handle: jlong, run: impl FnOnce(&T) -> R) -> Option<R> {
    if handle == 0 {
        return None;
    }
    Some(run(&*(handle as *const T)))
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

/// Wraps one entry point so a panic becomes a null answer instead of unwinding into the JVM.
fn guarded<T>(value: impl FnOnce() -> Option<T>) -> Option<T> {
    catch_unwind(AssertUnwindSafe(value)).ok().flatten()
}

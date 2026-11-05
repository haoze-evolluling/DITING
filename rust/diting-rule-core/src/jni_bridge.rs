//! JNI entry point for the Kotlin rule-index writer (`RustRuleIndexCompiler.kt`).
//!
//! Kotlin packs the enabled rules the DB loader hands it into one byte array (format documented on
//! [`crate::dtri::compile_packed`]), calls [`Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile`],
//! and writes the returned DTRI image to the index file. Every failure path returns null, which
//! the Kotlin side turns into an [IllegalStateException]: the writer is the only implementation, so
//! a missing library or a malformed payload must fail the snapshot build.

use jni::objects::{JByteArray, JObject};
use jni::sys::jbyteArray;
use jni::JNIEnv;

/// `com.haoze.diting.core.rule.RustRuleIndexCompiler.compile(ByteArray): ByteArray?`
///
/// Returns null instead of throwing, and never lets a Rust panic unwind through the JVM.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let compiled = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let image = crate::dtri::compile_packed(&payload)?;
        env.byte_array_from_slice(&image).ok()
    }));
    match compiled {
        Ok(Some(array)) => array.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

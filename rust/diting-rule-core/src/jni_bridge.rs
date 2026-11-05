//! JNI entry point for the Kotlin rule-index compiler (`RustRuleIndexCompiler.kt`).
//!
//! Kotlin packs the enabled rules the DB loader hands it into one byte array (format documented on
//! [`crate::dtri::compile_packed`]), calls [`Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile`],
//! and writes the returned DTRI image to the index file. Every failure path returns null: the
//! Kotlin side then runs its own compiler, so a missing library, an old `.so` without this symbol
//! or a malformed payload can never break a rule snapshot.

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

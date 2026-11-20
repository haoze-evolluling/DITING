use jni::objects::{JByteArray, JObject};
use jni::sys::{jbyteArray, jint};
use jni::JNIEnv;

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

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleSnapshotNative_build<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let built = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let input = crate::snapshot::payload::decode(&payload)?;
        let document = crate::snapshot::build(&input);
        env.byte_array_from_slice(document.as_bytes()).ok()
    }));
    match built {
        Ok(Some(array)) => array.into_raw(),
        _ => std::ptr::null_mut(),
    }
}


fn with_payload<F>(env: &JNIEnv<'_>, packed: &JByteArray<'_>, run: F) -> Option<Vec<u8>>
where
    F: FnOnce(&[u8]) -> Option<Vec<u8>>,
{
    let payload = env.convert_byte_array(packed).ok()?;
    run(&payload)
}

fn answer(env: &JNIEnv<'_>, value: Option<Vec<u8>>) -> jbyteArray {
    match value.and_then(|bytes| env.byte_array_from_slice(&bytes).ok()) {
        Some(array) => array.into_raw(),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_paths<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    dataset_tag: jint,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let tag = u8::try_from(dataset_tag).ok()?;
        crate::jni_payload::layout_paths(tag)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_dtriValidate<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_payload(&env, &packed, crate::jni_payload::dtri_validate)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_snapshotPlan<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_payload(&env, &packed, crate::jni_payload::snapshot_plan)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_triePaths<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_payload(&env, &packed, crate::jni_payload::trie_paths)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_appAllowlist<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_payload(&env, &packed, crate::jni_payload::app_allowlist)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_ruleFingerprint<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_payload(&env, &packed, crate::jni_payload::rule_fingerprint)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_rewriteRules<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer_bytes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        with_payload(&env, &packed, crate::jni_payload::rewrite_rules)
    }));
    answer(&env, answer_bytes.ok().flatten())
}

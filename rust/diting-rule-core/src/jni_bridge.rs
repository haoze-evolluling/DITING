use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JByteArray, JObject};
use jni::sys::jint;
use jni::{Env, EnvUnowned};

fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

fn answer_bytes<'local>(env: &mut Env<'local>, bytes: &[u8]) -> JObject<'local> {
    match env.byte_array_from_slice(bytes) {
        Ok(array) => JObject::from(array),
        Err(_) => JObject::null(),
    }
}

fn run_payload<'local>(
    env: &mut Env<'local>,
    packed: &JByteArray<'_>,
    run: impl FnOnce(&[u8]) -> Option<Vec<u8>>,
) -> Result<JObject<'local>, Error> {
    let payload = env.convert_byte_array(packed)?;
    Ok(match run(&payload) {
        Some(bytes) => answer_bytes(env, &bytes),
        None => JObject::null(),
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::dtri::compile_packed)
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleSnapshotNative_build<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = env.convert_byte_array(&packed)?;
        let Some(input) = crate::snapshot::payload::decode(&payload) else {
            return Ok(JObject::null());
        };
        let document = crate::snapshot::build(&input);
        Ok(answer_bytes(env, document.as_bytes()))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_paths<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    dataset_tag: jint,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let Some(tag) = u8::try_from(dataset_tag).ok() else {
            return Ok(JObject::null());
        };
        match crate::jni_payload::layout_paths(tag) {
            Some(bytes) => Ok(answer_bytes(env, &bytes)),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_dtriValidate<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::jni_payload::dtri_validate)
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_snapshotPlan<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::jni_payload::snapshot_plan)
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_triePaths<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::jni_payload::trie_paths)
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_appAllowlist<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::jni_payload::app_allowlist)
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_ruleFingerprint<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::jni_payload::rule_fingerprint)
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_core_rule_RuleIndexNative_rewriteRules<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        run_payload(env, &packed, crate::jni_payload::rewrite_rules)
    })
}

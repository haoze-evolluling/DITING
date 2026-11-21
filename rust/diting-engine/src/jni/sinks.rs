use std::sync::Arc;

use jni::objects::JObject;
use jni::sys::jlong;
use jni::EnvUnowned;

use super::{adapters, callbacks, lookup_checked, resolve};

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBatchLogCallback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        if let Some(instance) = lookup_checked(env, handle) {
            callbacks::set_sink(
                env,
                &instance.engine,
                &instance.sink,
                callbacks::Slot::Batch,
                callback,
            );
        };
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetRaceLogCallback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        if let Some(instance) = lookup_checked(env, handle) {
            callbacks::set_sink(
                env,
                &instance.engine,
                &instance.sink,
                callbacks::Slot::Race,
                callback,
            );
        };
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBootstrapLogCallback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        if let Some(instance) = lookup_checked(env, handle) {
            callbacks::set_sink(
                env,
                &instance.engine,
                &instance.sink,
                callbacks::Slot::Bootstrap,
                callback,
            );
        };
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetSocketProtector<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        let Some(instance) = lookup_checked(env, handle) else {
            return Ok(());
        };
        if callback.is_null() {
            instance.engine.protector().clear();
            return Ok(());
        }
        if let Some(protector) = adapters::protector(env, &callback) {
            instance.engine.protector().install(protector);
        } else {
            let _ = env.throw_new(
                jni::jni_str!("java/lang/IllegalStateException"),
                jni::jni_str!("setSocketProtector: the callback could not be captured"),
            );
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetUidResolver<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        let Some(instance) = lookup_checked(env, handle) else {
            return Ok(());
        };
        if callback.is_null() {
            instance.engine.attribution().clear_uid_resolver();
            return Ok(());
        }
        match adapters::JniUidResolver::new(env, &callback) {
            Ok(resolver) => instance
                .engine
                .attribution()
                .install_uid_resolver(Arc::new(resolver)),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!("setUIDResolver: the callback could not be captured"),
                );
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetAppUidResolver<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        let Some(instance) = lookup_checked(env, handle) else {
            return Ok(());
        };
        if callback.is_null() {
            instance.engine.attribution().clear_app_resolver();
            return Ok(());
        }
        match adapters::JniAppUidResolver::new(env, &callback) {
            Ok(resolver) => instance
                .engine
                .attribution()
                .install_app_resolver(Arc::new(resolver)),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!("setAppUidResolver: the callback could not be captured"),
                );
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetTrafficCallback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        let Some(instance) = lookup_checked(env, handle) else {
            return Ok(());
        };
        if callback.is_null() {
            instance.engine.set_traffic_sink(None);
            return Ok(());
        }
        match adapters::JniTrafficSink::new(env, &callback) {
            Ok(sink) => instance.engine.set_traffic_sink(Some(Arc::new(sink))),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!("setTrafficCallback: the callback could not be captured"),
                );
            }
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetOutboundProxyStatusCallback<
    'local,
>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        let Some(instance) = lookup_checked(env, handle) else {
            return Ok(());
        };
        if callback.is_null() {
            instance.engine.set_outbound_status_sink(None);
            return Ok(());
        }
        match adapters::JniOutboundStatus::new(env, &callback) {
            Ok(sink) => instance
                .engine
                .set_outbound_status_sink(Some(Arc::new(sink))),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!(
                        "setOutboundProxyStatusCallback: the callback could not be captured"
                    ),
                );
            }
        }
        Ok(())
    })
}

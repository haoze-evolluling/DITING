use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong};
use jni::EnvUnowned;

use super::{answer, resolve, text, with_engine};

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetRewriteRules<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JString<'local>,
) {
    resolve(&mut env, |env| {
        let payload = text(env, &payload);
        with_engine(env, handle, (), |engine| {
            engine.set_rewrite_rules(&payload)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetFilterDns<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    enabled: jboolean,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.set_filter_dns(enabled));
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockPause<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    until_ms: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| {
            engine.set_block_pause_until(until_ms)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetAllowlistOnly<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    enabled: jboolean,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| {
            engine.set_allowlist_only(enabled)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockResponseType<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    response_type: JString<'local>,
) {
    resolve(&mut env, |env| {
        let response_type = text(env, &response_type);
        with_engine(env, handle, (), |engine| {
            engine.set_block_response_type(&response_type)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeClearDnsCache<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.clear_dns_cache());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockedUids<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    csv: JString<'local>,
) {
    resolve(&mut env, |env| {
        let csv = text(env, &csv);
        with_engine(env, handle, (), |engine| engine.set_blocked_uids(&csv));
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetFilterHttp3<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    enabled: jboolean,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| {
            engine.set_filter_http3(enabled)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockEncryptedDns<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    enabled: jboolean,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| {
            engine.set_block_encrypted_dns(enabled)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockIpv6<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    enabled: jboolean,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.set_block_ipv6(enabled));
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetSystemDns<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    servers: JString<'local>,
) {
    resolve(&mut env, |env| {
        let servers = text(env, &servers);
        with_engine(env, handle, (), |engine| {
            engine.set_system_dns(&servers)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeResetResolverHealth<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.reset_resolver_health());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetTickIntervalMs<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    millis: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| {
            engine.set_tick_interval_ms(millis)
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeConfigureOutboundProxy<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = text(env, &payload);
        let error = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            let message = engine.configure_outbound_proxy(&payload);
            (!message.is_empty()).then_some(message)
        });
        Ok(answer(env, error))
    })
}

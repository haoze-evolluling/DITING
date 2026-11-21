use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JByteArray, JObject, JString};
use jni::sys::jboolean;
use jni::{Env, EnvUnowned};

fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

fn text(env: &mut Env<'_>, value: &JString<'_>) -> String {
    value.try_to_string(env).unwrap_or_default()
}

fn answer_bytes<'local>(env: &mut Env<'local>, bytes: &[u8]) -> JObject<'local> {
    match env.byte_array_from_slice(bytes) {
        Ok(array) => JObject::from(array),
        Err(_) => JObject::null(),
    }
}

fn answer_string<'local>(env: &mut Env<'local>, value: String) -> JObject<'local> {
    match env.new_string(value) {
        Ok(text) => JObject::from(text),
        Err(_) => JObject::null(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_sanitizeHost<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    input: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let text = text(env, &input);
        Ok(answer_string(env, crate::api::sanitize_host(&text)))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_isIpLiteral<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    input: JString<'local>,
) -> jboolean {
    resolve(&mut env, |env| {
        let text = text(env, &input);
        Ok(crate::api::is_ip_literal(&text))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_traceResponseLine<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    line: JString<'local>,
) -> jboolean {
    resolve(&mut env, |env| {
        let text = text(env, &line);
        Ok(crate::api::trace_response_line(&text))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_dohEndpoint<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    url: JString<'local>,
    host: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let url = text(env, &url);
        let host = text(env, &host);
        Ok(answer_string(env, crate::api::doh_endpoint(&url, &host)))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_buildDnsQuery<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = env.convert_byte_array(&packed)?;
        match crate::api::build_dns_query(&payload) {
            Some(query) => Ok(answer_bytes(env, &query)),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_dnsResponseSucceeded<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    response: JByteArray<'local>,
) -> jboolean {
    resolve(&mut env, |env| {
        let wire = env.convert_byte_array(&response)?;
        Ok(crate::api::dns_response_succeeded(&wire))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_parseDnsServerReply<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = env.convert_byte_array(&packed)?;
        match crate::api::parse_dns_server_reply(&payload) {
            Some(reply) => Ok(answer_bytes(env, &reply)),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_pingSummary<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = env.convert_byte_array(&packed)?;
        match crate::api::ping_summary(&payload) {
            Some(summary) => Ok(answer_bytes(env, &summary)),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_latencyStats<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = env.convert_byte_array(&packed)?;
        match crate::api::latency_stats(&payload) {
            Some(stats) => Ok(answer_bytes(env, &stats)),
            None => Ok(JObject::null()),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_traceHop<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = env.convert_byte_array(&packed)?;
        match crate::api::trace_hop(&payload) {
            Some(hop) => Ok(answer_bytes(env, &hop)),
            None => Ok(JObject::null()),
        }
    })
}

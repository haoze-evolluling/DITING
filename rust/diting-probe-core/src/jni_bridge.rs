//! JNI entry points for the Kotlin diagnostics tools (`com.haoze.diting.net.ProbeNative`).
//!
//! Every request is one `ByteArray` (or one `String`) and every answer is one `ByteArray` (or one
//! `String`); the layouts live in [`crate::api`]. A null answer means "the kernel could not decode
//! this call" — a missing library, a payload from a newer Kotlin side, or a panic — and
//! `ProbeNative.kt` turns that into an `IllegalStateException` instead of guessing.
//!
//! There is no C ABI here: only Kotlin calls this kernel, so the JDK's naming convention is the
//! whole boundary.

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JByteArray, JObject, JString};
use jni::sys::{jboolean, jbyteArray, jstring, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;

/// `ProbeNative.sanitizeHost(String): String?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_sanitizeHost<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    input: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text: String = env.get_string(&input).ok()?.into();
        env.new_string(crate::api::sanitize_host(&text)).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

/// `ProbeNative.isIpLiteral(String): Boolean`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_isIpLiteral<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    input: JString<'local>,
) -> jboolean {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text: String = env.get_string(&input).ok()?.into();
        Some(crate::api::is_ip_literal(&text))
    }));
    match answer {
        Ok(Some(true)) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

/// `ProbeNative.traceResponseLine(String): Boolean`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_traceResponseLine<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    line: JString<'local>,
) -> jboolean {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let text: String = env.get_string(&line).ok()?.into();
        Some(crate::api::trace_response_line(&text))
    }));
    match answer {
        Ok(Some(true)) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

/// `ProbeNative.dohEndpoint(String, String): String?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_dohEndpoint<'local>(
    mut env: JNIEnv<'local>,
    _this: JObject<'local>,
    url: JString<'local>,
    host: JString<'local>,
) -> jstring {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let url: String = env.get_string(&url).ok()?.into();
        let host: String = env.get_string(&host).ok()?.into();
        env.new_string(crate::api::doh_endpoint(&url, &host)).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

/// `ProbeNative.buildDnsQuery(ByteArray): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_buildDnsQuery<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let query = crate::api::build_dns_query(&payload)?;
        env.byte_array_from_slice(&query).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

/// `ProbeNative.dnsResponseSucceeded(ByteArray): Boolean`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_dnsResponseSucceeded<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    response: JByteArray<'local>,
) -> jboolean {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let wire = env.convert_byte_array(&response).ok()?;
        Some(crate::api::dns_response_succeeded(&wire))
    }));
    match answer {
        Ok(Some(true)) => JNI_TRUE,
        _ => JNI_FALSE,
    }
}

/// `ProbeNative.parseDnsServerReply(ByteArray): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_parseDnsServerReply<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let reply = crate::api::parse_dns_server_reply(&payload)?;
        env.byte_array_from_slice(&reply).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

/// `ProbeNative.pingSummary(ByteArray): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_pingSummary<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let summary = crate::api::ping_summary(&payload)?;
        env.byte_array_from_slice(&summary).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

/// `ProbeNative.latencyStats(ByteArray): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_latencyStats<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let stats = crate::api::latency_stats(&payload)?;
        env.byte_array_from_slice(&stats).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

/// `ProbeNative.traceHop(ByteArray): ByteArray?`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_net_ProbeNative_traceHop<'local>(
    env: JNIEnv<'local>,
    _this: JObject<'local>,
    packed: JByteArray<'local>,
) -> jbyteArray {
    let answer = catch_unwind(AssertUnwindSafe(|| {
        let payload = env.convert_byte_array(&packed).ok()?;
        let hop = crate::api::trace_hop(&payload)?;
        env.byte_array_from_slice(&hop).ok()
    }));
    match answer {
        Ok(Some(value)) => value.into_raw(),
        _ => std::ptr::null_mut(),
    }
}

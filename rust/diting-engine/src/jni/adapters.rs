//! The four data-plane callbacks Kotlin installs on the engine.
//!
//! They are the ones gomobile generated for the Go engine, with the same argument lists:
//!
//! | Kotlin | descriptor |
//! |---|---|
//! | `SocketProtector.protect(long): boolean` | `(J)Z` |
//! | `UIDResolver.resolveUID(long, String, long, String, long): long` | `(JLjava/lang/String;JLjava/lang/String;J)J` |
//! | `AppUidResolver.packageForUid(long): String` | `(J)Ljava/lang/String;` |
//! | `TrafficCallback.onTrafficStatsTick(String)` | `(Ljava/lang/String;)V` |
//!
//! # Threads
//!
//! * `protect` is called **on the thread that is about to dial** (a tokio worker or the stack
//!   thread) and must stay synchronous: the socket is not connected until it returns.
//! * the UID/package lookups run on the stack thread.
//! * the traffic tick comes from the engine's ticker task.
//!
//! Each call attaches the calling thread permanently and clears a Java exception afterwards, so a
//! throwing Kotlin callback degrades to "unknown"/"denied" instead of poisoning the JNI environment
//! for the next call. This mirrors the log callbacks in [`super::callbacks`].

use std::sync::Arc;

use jni::objects::{GlobalRef, JObject, JValue};
use jni::{JNIEnv, JavaVM};

use crate::attribution::{AppUidResolver, UidResolver};
use crate::engine::TrafficSink;
use crate::protect::Protector;

/// `SocketProtector.protect(long): boolean`.
pub const PROTECT_SIGNATURE: &str = "(J)Z";
/// `UIDResolver.resolveUID(long, String, long, String, long): long`.
pub const UID_SIGNATURE: &str = "(JLjava/lang/String;JLjava/lang/String;J)J";
/// `AppUidResolver.packageForUid(long): String`.
pub const APP_SIGNATURE: &str = "(J)Ljava/lang/String;";
/// `TrafficCallback.onTrafficStatsTick(String)`.
pub const TRAFFIC_SIGNATURE: &str = "(Ljava/lang/String;)V";

/// Captures the JVM and one callback object.
fn capture(
    env: &mut JNIEnv<'_>,
    callback: &JObject<'_>,
) -> Result<(JavaVM, GlobalRef), jni::errors::Error> {
    Ok((env.get_java_vm()?, env.new_global_ref(callback)?))
}

/// Attaches the calling thread and clears a pending Java exception afterwards.
fn with_env<R>(vm: &JavaVM, call: impl FnOnce(&mut JNIEnv<'_>) -> Option<R>, default: R) -> R {
    let mut env = match vm.attach_current_thread_permanently() {
        Ok(env) => env,
        Err(_) => return default,
    };
    let result = call(&mut env).unwrap_or(default);
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
    result
}

/// `VpnService.protect`, called before every outbound `connect`.
pub struct JniProtector {
    vm: JavaVM,
    target: GlobalRef,
}

impl JniProtector {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        Ok(Self { vm, target })
    }
}

impl Protector for JniProtector {
    fn protect(&self, fd: i64) -> bool {
        with_env(
            &self.vm,
            |env| {
                env.call_method(
                    self.target.as_obj(),
                    "protect",
                    PROTECT_SIGNATURE,
                    &[JValue::Long(fd)],
                )
                .ok()?
                .z()
                .ok()
            },
            // A throwing protector is a refusal: the dialer fails closed.
            false,
        )
    }
}

/// `ConnectivityManager.getConnectionOwnerUid` behind the optional kernel cache.
pub struct JniUidResolver {
    vm: JavaVM,
    target: GlobalRef,
}

impl JniUidResolver {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        Ok(Self { vm, target })
    }
}

impl UidResolver for JniUidResolver {
    fn resolve(
        &self,
        protocol: i32,
        app_ip: &str,
        app_port: u16,
        server_ip: &str,
        server_port: u16,
    ) -> i32 {
        with_env(
            &self.vm,
            |env| {
                let app = JObject::from(env.new_string(app_ip).ok()?);
                let server = JObject::from(env.new_string(server_ip).ok()?);
                let uid = env
                    .call_method(
                        self.target.as_obj(),
                        "resolveUID",
                        UID_SIGNATURE,
                        &[
                            JValue::Long(i64::from(protocol)),
                            JValue::Object(&app),
                            JValue::Long(i64::from(app_port)),
                            JValue::Object(&server),
                            JValue::Long(i64::from(server_port)),
                        ],
                    )
                    .ok()?
                    .j()
                    .ok()?;
                i32::try_from(uid).ok()
            },
            -1,
        )
    }
}

/// `PackageManager.getPackagesForUid` behind the optional kernel cache.
pub struct JniAppUidResolver {
    vm: JavaVM,
    target: GlobalRef,
}

impl JniAppUidResolver {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        Ok(Self { vm, target })
    }
}

impl AppUidResolver for JniAppUidResolver {
    fn package_for(&self, uid: i32) -> String {
        with_env(
            &self.vm,
            |env| {
                let value = env
                    .call_method(
                        self.target.as_obj(),
                        "packageForUid",
                        APP_SIGNATURE,
                        &[JValue::Long(i64::from(uid))],
                    )
                    .ok()?
                    .l()
                    .ok()?;
                if value.is_null() {
                    return Some(String::new());
                }
                env.get_string(&value.into()).ok().map(Into::into)
            },
            String::new(),
        )
    }
}

/// `TrafficCallback`, fed by the engine's per-UID ticker.
pub struct JniTrafficSink {
    vm: JavaVM,
    target: GlobalRef,
}

impl JniTrafficSink {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        Ok(Self { vm, target })
    }
}

impl TrafficSink for JniTrafficSink {
    fn tick(&self, json: &str) {
        with_env(
            &self.vm,
            |env| {
                let payload = JObject::from(env.new_string(json).ok()?);
                env.call_method(
                    self.target.as_obj(),
                    "onTrafficStatsTick",
                    TRAFFIC_SIGNATURE,
                    &[JValue::Object(&payload)],
                )
                .ok()?;
                Some(())
            },
            (),
        );
    }
}

/// Builds the shared `Arc` the engine stores; the caller installs it.
pub fn protector(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Option<Arc<dyn Protector>> {
    JniProtector::new(env, callback)
        .ok()
        .map(|protector| Arc::new(protector) as Arc<dyn Protector>)
}

/// `OutboundProxyStatusCallback.onOutboundProxyStatus(String, String)`.
pub const OUTBOUND_SIGNATURE: &str = "(Ljava/lang/String;Ljava/lang/String;)V";

/// The proxy status events (`disabled` / `connecting` / `ready` / `error`).
pub struct JniOutboundStatus {
    vm: JavaVM,
    target: GlobalRef,
}

impl JniOutboundStatus {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        Ok(Self { vm, target })
    }
}

impl crate::outbound::StatusSink for JniOutboundStatus {
    fn status(&self, state: &str, message: &str) {
        with_env(
            &self.vm,
            |env| {
                let state = JObject::from(env.new_string(state).ok()?);
                let message = JObject::from(env.new_string(message).ok()?);
                env.call_method(
                    self.target.as_obj(),
                    "onOutboundProxyStatus",
                    OUTBOUND_SIGNATURE,
                    &[JValue::Object(&state), JValue::Object(&message)],
                )
                .ok()?;
                Some(())
            },
            (),
        );
    }
}

/// `HttpLogCallback.onHttpEvent(String, String, String, String, String)`.
pub const HTTP_LOG_SIGNATURE: &str =
    "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V";

/// The MITM relay's decision rows: `(package, authority, protocol, outcome, matched rule)`.
pub struct JniHttpLog {
    vm: JavaVM,
    target: GlobalRef,
}

impl JniHttpLog {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        Ok(Self { vm, target })
    }
}

impl crate::mitm::HttpLogSink for JniHttpLog {
    fn event(&self, package: &str, authority: &str, protocol: &str, outcome: &str, rule: &str) {
        with_env(
            &self.vm,
            |env| {
                let package = JObject::from(env.new_string(package).ok()?);
                let authority = JObject::from(env.new_string(authority).ok()?);
                let protocol = JObject::from(env.new_string(protocol).ok()?);
                let outcome = JObject::from(env.new_string(outcome).ok()?);
                let rule = JObject::from(env.new_string(rule).ok()?);
                env.call_method(
                    self.target.as_obj(),
                    "onHttpEvent",
                    HTTP_LOG_SIGNATURE,
                    &[
                        JValue::Object(&package),
                        JValue::Object(&authority),
                        JValue::Object(&protocol),
                        JValue::Object(&outcome),
                        JValue::Object(&rule),
                    ],
                )
                .ok()?;
                Some(())
            },
            (),
        );
    }
}

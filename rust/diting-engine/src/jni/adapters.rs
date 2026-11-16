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

use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

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

/// `HttpLogCallback.onHttpEvents(byte[])`.
pub const HTTP_LOG_SIGNATURE: &str = "([B)V";

/// Events one batch may carry before the flusher hands them to Kotlin.
const HTTP_BATCH_SIZE: usize = 64;
/// How long a partial batch waits for more relay decisions.
const HTTP_FLUSH_INTERVAL: Duration = Duration::from_millis(200);
/// Events the relay may buffer ahead of the flusher before rows start being dropped.
const HTTP_CHANNEL_CAPACITY: usize = 1_024;
/// `package`, `authority`, `protocol`, `outcome`, `rule`.
const HTTP_FIELDS: usize = 5;

/// One relay decision, buffered on the relay thread and batched on the flusher thread.
struct HttpEvent {
    package: String,
    authority: String,
    protocol: String,
    outcome: String,
    rule: String,
}

/// The MITM relay's decision rows: `(package, authority, protocol, outcome, matched rule)`.
///
/// The relay produces dozens of decisions per page load, so the callback is fed through a
/// dedicated flusher: each relay call only appends to a channel, and one JNI call carries a whole
/// batch as a packed `byte[]`. That removes two crossings and five Java strings per decision while
/// keeping [`crate::mitm::HttpLogSink`] unchanged for the engine and its host tests.
pub struct JniHttpLog {
    sender: Option<SyncSender<HttpEvent>>,
    flusher: Mutex<Option<JoinHandle<()>>>,
}

impl JniHttpLog {
    pub fn new(env: &mut JNIEnv<'_>, callback: &JObject<'_>) -> Result<Self, jni::errors::Error> {
        let (vm, target) = capture(env, callback)?;
        let vm = Arc::new(vm);
        let (sender, receiver) = mpsc::sync_channel(HTTP_CHANNEL_CAPACITY);
        let flusher = thread::Builder::new()
            .name("diting-http-log".to_string())
            .spawn(move || flush_http_events(&vm, &target, receiver))
            .map_err(|_| jni::errors::Error::JniCall(jni::errors::JniError::Unknown))?;
        Ok(Self {
            sender: Some(sender),
            flusher: Mutex::new(Some(flusher)),
        })
    }
}

impl crate::mitm::HttpLogSink for JniHttpLog {
    fn event(&self, package: &str, authority: &str, protocol: &str, outcome: &str, rule: &str) {
        let Some(sender) = &self.sender else {
            return;
        };
        // A full channel drops the row rather than stalling the TLS relay.
        let _ = sender.try_send(HttpEvent {
            package: package.to_string(),
            authority: authority.to_string(),
            protocol: protocol.to_string(),
            outcome: outcome.to_string(),
            rule: rule.to_string(),
        });
    }
}

impl Drop for JniHttpLog {
    fn drop(&mut self) {
        // Closing the channel ends the flusher after its final batch.
        self.sender.take();
        let flusher = self
            .flusher
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        if let Some(handle) = flusher {
            let _ = handle.join();
        }
    }
}

fn flush_http_events(vm: &Arc<JavaVM>, target: &GlobalRef, receiver: Receiver<HttpEvent>) {
    let mut batch = Vec::with_capacity(HTTP_BATCH_SIZE);
    // Block until the first row of a batch, then drain everything already queued.
    while let Ok(event) = receiver.recv() {
        batch.push(event);
        let deadline = Instant::now() + HTTP_FLUSH_INTERVAL;
        while batch.len() < HTTP_BATCH_SIZE {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                break;
            }
            match receiver.recv_timeout(remaining) {
                Ok(event) => batch.push(event),
                Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => break,
            }
        }
        deliver_http_events(vm, target, &batch);
        batch.clear();
    }
}

/// `u32 count` then, per event, the five `u32 length | UTF-8` fields.
fn deliver_http_events(vm: &JavaVM, target: &GlobalRef, batch: &[HttpEvent]) {
    let mut payload = Vec::with_capacity(4 + batch.len() * HTTP_FIELDS * 16);
    payload.extend_from_slice(&(batch.len() as u32).to_be_bytes());
    for event in batch {
        for field in [
            &event.package,
            &event.authority,
            &event.protocol,
            &event.outcome,
            &event.rule,
        ] {
            payload.extend_from_slice(&(field.len() as u32).to_be_bytes());
            payload.extend_from_slice(field.as_bytes());
        }
    }
    with_env(
        vm,
        |env| {
            let rows = env.byte_array_from_slice(&payload).ok()?;
            let rows = JObject::from(rows);
            env.call_method(
                target.as_obj(),
                "onHttpEvents",
                HTTP_LOG_SIGNATURE,
                &[JValue::Object(&rows)],
            )
            .ok()?;
            Some(())
        },
        (),
    );
}

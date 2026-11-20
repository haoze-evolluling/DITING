use std::collections::HashMap;
use std::net::SocketAddr;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use jni::objects::{GlobalRef, JObject, JString, JValue};
use jni::sys::{jboolean, jint, jlong, jstring};
use jni::{JNIEnv, JavaVM};

use crate::callback::{CallbackStats, Dispatcher};
use crate::io::{LoopbackHandle, PacketSource};
use crate::pipeline::{self, Config, Running, DEFAULT_CALLBACK_CAPACITY};
use crate::protector::{Evidence, NoProtection, Protector};
use crate::stats::{stats_json, Counters};
use crate::RawSocket;

pub const SESSION_CLASS: &str = "com/haoze/diting/engine/TunSession";
pub const CALLBACK_SIGNATURE: &str = "(Ljava/lang/String;)V";
pub const PROTECT_SIGNATURE: &str = "(J)Z";
pub const CALLBACK_THREAD: &str = "diting-tun-callback";
pub const MTU: usize = 1500;

struct Session {
    vm: Option<Arc<JavaVM>>,
    source: LoopbackHandle,
    protector: Mutex<Arc<dyn Protector>>,
    callback: Mutex<Option<GlobalRef>>,
    running: Mutex<Option<Running>>,
}

type Registry = Mutex<HashMap<u64, Arc<Session>>>;

fn registry() -> &'static Registry {
    static REGISTRY: OnceLock<Registry> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_handle() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

pub fn live_sessions() -> usize {
    registry()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .len()
}

fn lookup(handle: jlong) -> Option<Arc<Session>> {
    let handle = u64::try_from(handle).ok()?;
    registry()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .get(&handle)
        .cloned()
}

fn insert(session: Session) -> u64 {
    let handle = next_handle();
    registry()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .insert(handle, Arc::new(session));
    handle
}

fn remove(handle: jlong) -> Option<Arc<Session>> {
    let handle = u64::try_from(handle).ok()?;
    registry()
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .remove(&handle)
}

fn with_session<R>(
    env: &mut JNIEnv<'_>,
    handle: jlong,
    default: R,
    run: impl FnOnce(&Arc<Session>) -> R,
) -> R {
    match catch_unwind(AssertUnwindSafe(|| lookup(handle).map(|s| run(&s)))) {
        Ok(Some(value)) => value,
        Ok(None) => default,
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "diting tun session panicked; see logcat",
            );
            default
        }
    }
}

fn text(env: &mut JNIEnv<'_>, value: &JString<'_>) -> String {
    env.get_string(value)
        .map(|text| text.into())
        .unwrap_or_default()
}

fn answer(env: &JNIEnv<'_>, value: Option<String>) -> jstring {
    match value.and_then(|value| env.new_string(value).ok()) {
        Some(text) => text.into_raw(),
        None => std::ptr::null_mut(),
    }
}


struct JniProtector {
    vm: Arc<JavaVM>,
    target: GlobalRef,
}

impl Protector for JniProtector {
    fn protect(&self, fd: RawSocket) -> bool {
        let Ok(mut env) = self.vm.attach_current_thread_permanently() else {
            return false;
        };
        let outcome = env.call_method(
            self.target.as_obj(),
            "protect",
            PROTECT_SIGNATURE,
            &[JValue::Long(fd as i64)],
        );
        let allowed = match outcome {
            Ok(value) => value.z().unwrap_or(false),
            Err(_) => false,
        };
        if env.exception_check().unwrap_or(false) {
            let _ = env.exception_clear();
            return false;
        }
        allowed
    }
}

fn callback_factory(vm: Arc<JavaVM>, target: GlobalRef) -> impl FnMut(&str) + Send + 'static {
    let _ = vm.attach_current_thread_permanently();
    move |payload: &str| {
        let Ok(mut env) = vm.attach_current_thread_permanently() else {
            return;
        };
        let Ok(text) = env.new_string(payload) else {
            return;
        };
        let text = JObject::from(text);
        let _ = env.call_method(
            target.as_obj(),
            "onPacket",
            CALLBACK_SIGNATURE,
            &[JValue::Object(&text)],
        );
        if env.exception_check().unwrap_or(false) {
            let _ = env.exception_clear();
        }
    }
}


#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeNew(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
) -> jlong {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let vm = env.get_java_vm().ok().map(Arc::new);
        insert(Session {
            vm,
            source: LoopbackHandle::new(),
            protector: Mutex::new(Arc::new(NoProtection)),
            callback: Mutex::new(None),
            running: Mutex::new(None),
        })
    }));
    match result {
        Ok(handle) => handle as jlong,
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "diting tun session failed to start",
            );
            0
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeFree(
    _env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(session) = remove(handle) {
            let running = session
                .running
                .lock()
                .unwrap_or_else(|err| err.into_inner())
                .take();
            if let Some(running) = running {
                running.stop();
            }
        }
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeSetProtector(
    env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    protector: JObject<'_>,
) {
    if let Some(session) = catch_unwind(AssertUnwindSafe(|| lookup(handle)))
        .ok()
        .flatten()
    {
        let replacement: Arc<dyn Protector> = if protector.is_null() {
            Arc::new(NoProtection)
        } else {
            let target = match env.new_global_ref(&protector) {
                Ok(reference) => reference,
                Err(_) => return,
            };
            match session.vm.clone() {
                Some(vm) => Arc::new(JniProtector { vm, target }),
                None => Arc::new(NoProtection),
            }
        };
        *session
            .protector
            .lock()
            .unwrap_or_else(|err| err.into_inner()) = replacement;
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeSetCallback(
    env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    if let Some(session) = catch_unwind(AssertUnwindSafe(|| lookup(handle)))
        .ok()
        .flatten()
    {
        let reference = if callback.is_null() {
            None
        } else {
            env.new_global_ref(&callback).ok()
        };
        *session
            .callback
            .lock()
            .unwrap_or_else(|err| err.into_inner()) = reference;
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeStart(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    target: JString<'_>,
) -> jstring {
    let target = text(&mut env, &target);
    let error = with_session(
        &mut env,
        handle,
        Some("session released".to_string()),
        |session| start_session(session, &target).err(),
    );
    answer(&env, error)
}

fn start_session(session: &Arc<Session>, target: &str) -> Result<(), String> {
    let address: SocketAddr = target
        .parse()
        .map_err(|err| format!("invalid dial target '{target}': {err}"))?;
    let mut slot = session
        .running
        .lock()
        .unwrap_or_else(|err| err.into_inner());
    if slot.is_some() {
        return Err("the session is already running".to_string());
    }

    let jvm_and_callback = session.vm.clone().zip(
        session
            .callback
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .clone(),
    );
    let dispatcher = match jvm_and_callback {
        Some((vm, callback)) => {
            Dispatcher::spawn(CALLBACK_THREAD, DEFAULT_CALLBACK_CAPACITY, move || {
                callback_factory(vm, callback)
            })?
        }
        None => Dispatcher::spawn(CALLBACK_THREAD, DEFAULT_CALLBACK_CAPACITY, || {
            |_payload: &str| {}
        })?,
    };

    let protector = session
        .protector
        .lock()
        .unwrap_or_else(|err| err.into_inner())
        .clone();
    let source: Arc<dyn PacketSource> = Arc::new(session.source.source());
    let running = pipeline::start(source, protector, Config::new(address, MTU), dispatcher)?;
    *slot = Some(running);
    Ok(())
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeStop(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    with_session(&mut env, handle, (), |session| {
        let running = session
            .running
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .take();
        if let Some(running) = running {
            running.stop();
        }
    });
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeFeed(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    count: jint,
) {
    with_session(&mut env, handle, (), |session| {
        for sequence in 0..count.max(0) {
            let mut packet = [0u8; 64];
            packet[0] = (sequence & 0xff) as u8;
            packet[1] = ((sequence >> 8) & 0xff) as u8;
            if !session.source.push(packet) {
                break;
            }
        }
    });
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeGetStats(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) -> jstring {
    let live = live_sessions();
    let document = with_session(&mut env, handle, Some("{}".to_string()), |session| {
        let running = session
            .running
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .as_ref()
            .map(|running| {
                (
                    running.counters.clone(),
                    running.evidence.clone(),
                    running.callbacks().stats(),
                    running.connection.get(),
                    running.error(),
                )
            });
        Some(match running {
            Some((counters, evidence, callbacks, connected, error)) => stats_json(
                live,
                &counters,
                &evidence,
                &callbacks,
                connected,
                error.as_deref(),
            ),
            None => stats_json(
                live,
                &Counters::default(),
                &Evidence::default(),
                &CallbackStats::default(),
                false,
                None,
            ),
        })
    });
    answer(&env, document)
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeWaitForCallbacks(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    delivered: jlong,
    timeout_ms: jlong,
) -> jboolean {
    let wanted = delivered.max(0) as u64;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms.max(0) as u64);
    with_session(&mut env, handle, 0, |session| loop {
        let arrived = session
            .running
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .as_ref()
            .map(|running| running.callbacks().stats().delivered)
            .unwrap_or(0);
        if arrived >= wanted {
            return 1;
        }
        if Instant::now() >= deadline {
            return 0;
        }
        std::thread::sleep(Duration::from_millis(5));
    })
}

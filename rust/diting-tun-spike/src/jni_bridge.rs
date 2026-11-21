use std::collections::HashMap;
use std::net::SocketAddr;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{Global, JObject, JString, JValue};
use jni::sys::{jboolean, jint, jlong};
use jni::{Env, EnvUnowned, JavaVM};

use crate::callback::{CallbackStats, Dispatcher};
use crate::io::{LoopbackHandle, PacketSource};
use crate::pipeline::{self, Config, Running, DEFAULT_CALLBACK_CAPACITY};
use crate::protector::{Evidence, NoProtection, Protector};
use crate::stats::{stats_json, Counters};
use crate::RawSocket;

pub const SESSION_CLASS: &str = "com/haoze/diting/engine/TunSession";
pub const CALLBACK_THREAD: &str = "diting-tun-callback";
pub const MTU: usize = 1500;

type GlobalObject = Global<JObject<'static>>;

fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

struct Session {
    vm: Option<Arc<JavaVM>>,
    source: LoopbackHandle,
    protector: Mutex<Arc<dyn Protector>>,
    callback: Mutex<Option<Arc<GlobalObject>>>,
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
    env: &mut Env<'_>,
    handle: jlong,
    default: R,
    run: impl FnOnce(&Arc<Session>) -> R,
) -> R {
    match catch_unwind(AssertUnwindSafe(|| lookup(handle).map(|s| run(&s)))) {
        Ok(Some(value)) => value,
        Ok(None) => default,
        Err(_) => {
            let _ = env.throw_new(
                jni::jni_str!("java/lang/IllegalStateException"),
                jni::jni_str!("diting tun session panicked; see logcat"),
            );
            default
        }
    }
}

fn text(env: &mut Env<'_>, value: &JString<'_>) -> String {
    value.try_to_string(env).unwrap_or_default()
}

fn answer<'local>(env: &mut Env<'local>, value: Option<String>) -> JObject<'local> {
    match value.and_then(|value| env.new_string(value).ok()) {
        Some(text) => JObject::from(text),
        None => JObject::null(),
    }
}

struct JniProtector {
    vm: Arc<JavaVM>,
    target: GlobalObject,
}

impl Protector for JniProtector {
    fn protect(&self, fd: RawSocket) -> bool {
        let target = &self.target;
        self.vm
            .attach_current_thread(|env| -> Result<bool, Error> {
                let outcome = env.call_method(
                    target.as_obj(),
                    jni::jni_str!("protect"),
                    jni::jni_sig!("(J)Z"),
                    &[JValue::Long(fd as i64)],
                );
                let allowed = match outcome {
                    Ok(value) => value.z().unwrap_or(false),
                    Err(_) => false,
                };
                if env.exception_check() {
                    let _ = env.exception_clear();
                    return Ok(false);
                }
                Ok(allowed)
            })
            .unwrap_or(false)
    }
}

fn callback_factory(vm: Arc<JavaVM>, target: Arc<GlobalObject>) -> impl FnMut(&str) + Send + 'static {
    let _ = vm.attach_current_thread(|_env| -> Result<(), Error> { Ok(()) });
    move |payload: &str| {
        let target = &target;
        let _ = vm.attach_current_thread(|env| -> Result<(), Error> {
            let Ok(text) = env.new_string(payload) else {
                return Ok(());
            };
            let text = JObject::from(text);
            let _ = env.call_method(
                target.as_obj(),
                jni::jni_str!("onPacket"),
                jni::jni_sig!("(Ljava/lang/String;)V"),
                &[JValue::Object(&text)],
            );
            if env.exception_check() {
                let _ = env.exception_clear();
            }
            Ok(())
        });
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeNew<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
) -> jlong {
    resolve(&mut env, |env| {
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
            Ok(handle) => Ok(handle as jlong),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!("diting tun session failed to start"),
                );
                Ok(0)
            }
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeFree<'local>(
    _env: EnvUnowned<'local>,
    _class: JObject<'local>,
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
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeSetProtector<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    protector: JObject<'local>,
) {
    resolve(&mut env, |env| {
        if let Some(session) = catch_unwind(AssertUnwindSafe(|| lookup(handle)))
            .ok()
            .flatten()
        {
            let replacement: Arc<dyn Protector> = if protector.is_null() {
                Arc::new(NoProtection)
            } else {
                let target = match env.new_global_ref(&protector) {
                    Ok(reference) => reference,
                    Err(_) => return Ok(()),
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
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeSetCallback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    callback: JObject<'local>,
) {
    resolve(&mut env, |env| {
        if let Some(session) = catch_unwind(AssertUnwindSafe(|| lookup(handle)))
            .ok()
            .flatten()
        {
            let reference = if callback.is_null() {
                None
            } else {
                env.new_global_ref(&callback).ok().map(Arc::new)
            };
            *session
                .callback
                .lock()
                .unwrap_or_else(|err| err.into_inner()) = reference;
        }
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeStart<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    target: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let target = text(env, &target);
        let error = with_session(
            env,
            handle,
            Some("session released".to_string()),
            |session| start_session(session, &target).err(),
        );
        Ok(answer(env, error))
    })
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
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeStop<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_session(env, handle, (), |session| {
            let running = session
                .running
                .lock()
                .unwrap_or_else(|err| err.into_inner())
                .take();
            if let Some(running) = running {
                running.stop();
            }
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeFeed<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    count: jint,
) {
    resolve(&mut env, |env| {
        with_session(env, handle, (), |session| {
            for sequence in 0..count.max(0) {
                let mut packet = [0u8; 64];
                packet[0] = (sequence & 0xff) as u8;
                packet[1] = ((sequence >> 8) & 0xff) as u8;
                if !session.source.push(packet) {
                    break;
                }
            }
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeGetStats<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let live = live_sessions();
        let document = with_session(env, handle, Some("{}".to_string()), |session| {
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
        Ok(answer(env, document))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_TunSession_nativeWaitForCallbacks<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    delivered: jlong,
    timeout_ms: jlong,
) -> jboolean {
    resolve(&mut env, |env| {
        let wanted = delivered.max(0) as u64;
        let deadline = Instant::now() + Duration::from_millis(timeout_ms.max(0) as u64);
        Ok(with_session(env, handle, false, |session| loop {
            let arrived = session
                .running
                .lock()
                .unwrap_or_else(|err| err.into_inner())
                .as_ref()
                .map(|running| running.callbacks().stats().delivered)
                .unwrap_or(0);
            if arrived >= wanted {
                return true;
            }
            if Instant::now() >= deadline {
                return false;
            }
            std::thread::sleep(Duration::from_millis(5));
        }))
    })
}

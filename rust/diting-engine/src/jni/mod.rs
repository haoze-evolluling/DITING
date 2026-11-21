pub mod adapters;
pub mod config;
pub mod sinks;
pub mod callbacks;
pub mod mitm;
pub mod rule_test;
pub mod snapshot;

use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use jni::errors::{Error, LogErrorAndDefault};
use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong};
use jni::{Env, EnvUnowned};

use crate::engine::Engine;
use crate::logs::EventSink;

use callbacks::CallbackSink;

pub const ENGINE_CLASS: &str = "com/haoze/diting/engine/Engine";

pub(super) struct Instance {
    engine: Arc<Engine>,
    sink: Arc<CallbackSink>,
}

type Registry = Mutex<HashMap<u64, Arc<Instance>>>;

fn registry() -> &'static Registry {
    static REGISTRY: OnceLock<Registry> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_handle() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

fn insert(engine: Arc<Engine>, sink: Arc<CallbackSink>) -> u64 {
    let handle = next_handle();
    registry()
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .insert(handle, Arc::new(Instance { engine, sink }));
    handle
}

fn lookup(handle: jlong) -> Option<Arc<Instance>> {
    let handle = u64::try_from(handle).ok()?;
    registry()
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .get(&handle)
        .cloned()
}

fn remove(handle: jlong) -> Option<Arc<Instance>> {
    let handle = u64::try_from(handle).ok()?;
    registry()
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .remove(&handle)
}

pub fn live_engines() -> usize {
    registry()
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .len()
}

pub(super) fn resolve<'local, T: Default>(
    env: &mut EnvUnowned<'local>,
    run: impl FnOnce(&mut Env<'local>) -> Result<T, Error>,
) -> T {
    env.with_env(run).resolve::<LogErrorAndDefault>()
}

pub(super) fn with_engine<R>(
    env: &mut Env<'_>,
    handle: jlong,
    default: R,
    run: impl FnOnce(&Arc<Engine>) -> R,
) -> R {
    with_instance(env, handle, default, |instance| run(&instance.engine))
}

pub(super) fn lookup_checked(env: &mut Env<'_>, handle: jlong) -> Option<Arc<Instance>> {
    match catch_unwind(AssertUnwindSafe(|| lookup(handle))) {
        Ok(instance) => instance,
        Err(_) => {
            let _ = env.throw_new(
                jni::jni_str!("java/lang/IllegalStateException"),
                jni::jni_str!("diting engine panicked; see logcat"),
            );
            None
        }
    }
}

fn with_instance<R>(
    env: &mut Env<'_>,
    handle: jlong,
    default: R,
    run: impl FnOnce(&Arc<Instance>) -> R,
) -> R {
    match catch_unwind(AssertUnwindSafe(|| {
        lookup(handle).map(|instance| run(&instance))
    })) {
        Ok(Some(value)) => value,
        Ok(None) => default,
        Err(_) => {
            let _ = env.throw_new(
                jni::jni_str!("java/lang/IllegalStateException"),
                jni::jni_str!("diting engine panicked; see logcat"),
            );
            default
        }
    }
}

pub(super) fn text(env: &mut Env<'_>, value: &JString<'_>) -> String {
    value.try_to_string(env).unwrap_or_default()
}

pub(super) fn answer<'local>(env: &mut Env<'local>, value: Option<String>) -> JObject<'local> {
    match value.and_then(|value| env.new_string(value).ok()) {
        Some(text) => JObject::from(text),
        None => JObject::null(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeNew<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
) -> jlong {
    resolve(&mut env, |env| {
        crate::panic_log::install();
        let result = catch_unwind(AssertUnwindSafe(|| {
            let engine = Arc::new(Engine::new());
            let sink = CallbackSink::new(env)
                .map(Arc::new)
                .unwrap_or_else(|_| Arc::new(CallbackSink::headless()));
            insert(engine, sink)
        }));
        match result {
            Ok(handle) => Ok(handle as jlong),
            Err(_) => {
                let _ = env.throw_new(
                    jni::jni_str!("java/lang/IllegalStateException"),
                    jni::jni_str!("diting engine failed to start"),
                );
                Ok(0)
            }
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeFree<'local>(
    _env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(instance) = remove(handle) {
            instance.engine.stop();
        }
    }));
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStop<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.stop());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeFlushLogs<'local>(
    mut env: EnvUnowned<'local>,
    _this: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_instance(env, handle, (), |instance| {
            instance.engine.logs().flush();
            instance.sink.flush();
        });
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopStandalone<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.stop_standalone());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartStandalone<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    port: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let error = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            let port = u16::try_from(port).unwrap_or(0);
            engine
                .start_standalone(port)
                .err()
                .map(|error| error.to_string())
        });
        Ok(answer(env, error))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartStandaloneLoopback<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    port: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let error = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            let port = u16::try_from(port).unwrap_or(0);
            engine
                .start_standalone_loopback(port)
                .err()
                .map(|error| error.to_string())
        });
        Ok(answer(env, error))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStandalonePort<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> jlong {
    resolve(&mut env, |env| {
        Ok(with_engine(env, handle, 0 as jlong, |engine| {
            engine.standalone_port().map_or(0, jlong::from)
        }))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeIsRunning<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> jboolean {
    resolve(&mut env, |env| {
        Ok(with_engine(env, handle, false, |engine| {
            engine.is_running()
        }))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeApplyDnsConfig<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = text(env, &payload);
        let error = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            engine
                .apply_dns_config(&payload)
                .err()
                .map(|error| error.to_string())
        });
        Ok(answer(env, error))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeApplyRuleSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    payload: JString<'local>,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let payload = text(env, &payload);
        let answer_text = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            Some(engine.apply_rule_snapshot(&payload))
        });
        Ok(answer(env, answer_text))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetStats<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let document = with_engine(env, handle, Some("{}".to_string()), |engine| {
            Some(crate::stats::engine_stats_json(engine))
        });
        Ok(answer(env, document))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetDnsCacheStats<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let document = with_engine(env, handle, Some("{}".to_string()), |engine| {
            Some(crate::cache::stats_json(engine.cache().stats()))
        });
        Ok(answer(env, document))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetDnsCacheEntries<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    limit: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let document = with_engine(env, handle, Some("[]".to_string()), |engine| {
            if limit <= 0 {
                return Some("[]".to_string());
            }
            let entries = engine.cache().snapshot(limit.min(u32::MAX as i64) as u32);
            Some(crate::cache::entries_json(&entries))
        });
        Ok(answer(env, document))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeFlowSnapshot<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    since_seq: jlong,
    limit: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let document = with_engine(env, handle, Some("{}".to_string()), |engine| {
            let since = if since_seq <= 0 { 0 } else { since_seq as u64 };
            let cap = if limit <= 0 { 0 } else { limit as usize };
            Some(engine.flow_snapshot_json(since, cap))
        });
        Ok(answer(env, document))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeResolveDomain<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    domain: JString<'local>,
    ipv4: jboolean,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let domain = text(env, &domain);
        let document = with_engine(
            env,
            handle,
            Some(crate::engine::resolve_domain_error_json("engine released")),
            |engine| Some(engine.block_on(engine.resolve_domain(&domain, ipv4))),
        );
        Ok(answer(env, document))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartFull<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
    fd: jlong,
) -> JObject<'local> {
    resolve(&mut env, |env| {
        let error = with_engine(env, handle, Some("engine released".to_string()), |engine| {
            let fd = i32::try_from(fd).unwrap_or(-1);
            engine.start_full(fd).err().map(|error| error.to_string())
        });
        Ok(answer(env, error))
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopFull<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.stop_full());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeReleaseTun<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) {
    resolve(&mut env, |env| {
        with_engine(env, handle, (), |engine| engine.stop_full());
        Ok(())
    })
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeIsFullRunning<'local>(
    mut env: EnvUnowned<'local>,
    _class: JObject<'local>,
    handle: jlong,
) -> jboolean {
    resolve(&mut env, |env| {
        Ok(with_engine(env, handle, false, |engine| {
            engine.is_full_running()
        }))
    })
}

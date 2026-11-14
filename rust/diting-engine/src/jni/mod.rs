//! The JNI facade: one registry of engine handles and one entry point per Kotlin method.
//!
//! # Handles, not pointers
//!
//! `nativeNew` returns a `u64` and stores the engine in [`registry`], so a stale handle is a lookup
//! failure instead of a use-after-free. `nativeFree` removes it; an in-flight task keeps its own
//! `Arc<Engine>`, so the memory it needs stays alive until the task is done. This is the design the
//! migration plan asks for (section 5.1: "handle registry + `Arc`, not raw pointers").
//!
//! # Errors
//!
//! Every entry point runs under `catch_unwind`: a panic becomes a Java `IllegalStateException`
//! instead of unwinding into the JVM. `ApplyDNSConfig` and `StartStandalone` return the Go error text
//! as a `String` (null when they succeeded) and the Kotlin facade throws; the rest never fail.
//! A missing handle returns zero/null, which the facade reports as "engine released" — a caller that
//! kept a reference after `stop()` must not crash the process.
//!
//! # Threads
//!
//! The engine never calls back on the JNI thread: the batch log comes from the flusher thread, the
//! race log from a tokio worker. Callbacks are sent to those threads, which attach to the JVM
//! permanently on first use, and every callback clears a pending Java exception afterwards, so a
//! throwing Kotlin callback cannot poison the environment for the next call.

pub mod adapters;
pub mod callbacks;
pub mod mitm;
pub mod rule_test;

use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use jni::objects::{JObject, JString};
use jni::sys::{jboolean, jlong, jstring};
use jni::JNIEnv;

use crate::engine::Engine;

use callbacks::CallbackSink;

/// Kotlin's `Engine` class, which is also the class the JVM smoke test declares.
pub const ENGINE_CLASS: &str = "com/haoze/diting/engine/Engine";

/// One live engine and the Kotlin callbacks installed on it.
struct Instance {
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

/// How many engines are alive; used by the smoke test to catch a leaked `nativeFree`.
pub fn live_engines() -> usize {
    registry()
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .len()
}

/// Runs `run` with the handle's engine, returning `default` when the handle is stale or the entry
/// point panicked (the panic is raised in Java so it is not silent).
fn with_engine<R>(
    env: &mut JNIEnv<'_>,
    handle: jlong,
    default: R,
    run: impl FnOnce(&Arc<Engine>) -> R,
) -> R {
    with_instance(env, handle, default, |instance| run(&instance.engine))
}

/// Looks the handle up, turning a panic into a Java exception. Used by the entry points that need
/// `env` themselves (the callback installers), where a closure could not borrow it.
fn lookup_checked(env: &mut JNIEnv<'_>, handle: jlong) -> Option<Arc<Instance>> {
    match catch_unwind(AssertUnwindSafe(|| lookup(handle))) {
        Ok(instance) => instance,
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "diting engine panicked; see logcat",
            );
            None
        }
    }
}

/// The same, for the entry points that need the callback sink as well.
fn with_instance<R>(
    env: &mut JNIEnv<'_>,
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
                "java/lang/IllegalStateException",
                "diting engine panicked; see logcat",
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

// ---- lifecycle ---------------------------------------------------------------------------------

/// `Engine()`: allocates an engine and returns its handle.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeNew(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
) -> jlong {
    // One line on logcat before any unwind, so a caught engine panic is still visible in the
    // captured runtime log instead of vanishing into an IllegalStateException.
    crate::panic_log::install();
    let result = catch_unwind(AssertUnwindSafe(|| {
        let engine = Arc::new(Engine::new());
        // Without a JVM reference no callback can ever be delivered, but the engine still answers
        // queries; that is the only way a host test can drive it.
        let sink = CallbackSink::new(&mut env)
            .map(Arc::new)
            .unwrap_or_else(|_| Arc::new(CallbackSink::headless()));
        insert(engine, sink)
    }));
    match result {
        Ok(handle) => handle as jlong,
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "diting engine failed to start",
            );
            0
        }
    }
}

/// Releases the handle. In-flight tasks keep the engine alive until they finish.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeFree(
    _env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    let _ = catch_unwind(AssertUnwindSafe(|| remove(handle)));
}

/// `stop()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStop(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.stop());
}

/// `stopStandalone()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopStandalone(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.stop_standalone());
}

/// `startStandalone(port)`: null on success, otherwise the bind error text.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartStandalone(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    port: jlong,
) -> jstring {
    let error = with_engine(
        &mut env,
        handle,
        Some("engine released".to_string()),
        |engine| {
            let port = u16::try_from(port).unwrap_or(0);
            engine
                .start_standalone(port)
                .err()
                .map(|error| error.to_string())
        },
    );
    answer(&env, error)
}

/// `standalonePort()`: the port the server is listening on, 0 when it is not running.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStandalonePort(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) -> jlong {
    with_engine(&mut env, handle, 0 as jlong, |engine| {
        engine.standalone_port().map_or(0, jlong::from)
    })
}

/// `isRunning()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeIsRunning(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) -> jboolean {
    with_engine(&mut env, handle, 0, |engine| u8::from(engine.is_running()))
}

// ---- configuration -----------------------------------------------------------------------------

/// `applyDNSConfig(json)`: null on success, otherwise the error text (the Go method returned `error`).
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeApplyDnsConfig(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    payload: JString<'_>,
) -> jstring {
    let payload = text(&mut env, &payload);
    let error = with_engine(
        &mut env,
        handle,
        Some("engine released".to_string()),
        |engine| {
            engine
                .apply_dns_config(&payload)
                .err()
                .map(|error| error.to_string())
        },
    );
    answer(&env, error)
}

/// `applyRuleSnapshot(json)`: empty on success, otherwise the rejection text.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeApplyRuleSnapshot(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    payload: JString<'_>,
) -> jstring {
    let payload = text(&mut env, &payload);
    let answer_text = with_engine(
        &mut env,
        handle,
        Some("engine released".to_string()),
        |engine| Some(engine.apply_rule_snapshot(&payload)),
    );
    answer(&env, answer_text)
}

/// `setRewriteRules(json)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetRewriteRules(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    payload: JString<'_>,
) {
    let payload = text(&mut env, &payload);
    with_engine(&mut env, handle, (), |engine| {
        engine.set_rewrite_rules(&payload)
    });
}

/// `setFilterDNS(enabled)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetFilterDns(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    enabled: jboolean,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_filter_dns(enabled != 0)
    });
}

/// `setBlockPause(untilMs)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockPause(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    until_ms: jlong,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_block_pause_until(until_ms)
    });
}

/// `setAllowlistOnly(enabled)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetAllowlistOnly(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    enabled: jboolean,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_allowlist_only(enabled != 0)
    });
}

/// `setBlockResponseType(name)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockResponseType(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    response_type: JString<'_>,
) {
    let response_type = text(&mut env, &response_type);
    with_engine(&mut env, handle, (), |engine| {
        engine.set_block_response_type(&response_type)
    });
}

/// `clearDNSCache()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeClearDnsCache(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.clear_dns_cache());
}

// ---- read-only documents -----------------------------------------------------------------------

/// `getStats()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetStats(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) -> jstring {
    let document = with_engine(&mut env, handle, Some("{}".to_string()), |engine| {
        Some(crate::stats::engine_stats_json(engine))
    });
    answer(&env, document)
}

/// `getDNSCacheStats()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetDnsCacheStats(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) -> jstring {
    let document = with_engine(&mut env, handle, Some("{}".to_string()), |engine| {
        Some(crate::cache::stats_json(engine.cache().stats()))
    });
    answer(&env, document)
}

/// `getDNSCacheEntries(limit)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeGetDnsCacheEntries(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    limit: jlong,
) -> jstring {
    let document = with_engine(&mut env, handle, Some("[]".to_string()), |engine| {
        if limit <= 0 {
            return Some("[]".to_string());
        }
        let entries = engine.cache().snapshot(limit.min(u32::MAX as i64) as u32);
        Some(crate::cache::entries_json(&entries))
    });
    answer(&env, document)
}

/// `flowSnapshot(sinceSeq, limit)`: incremental live-connection document for the flow view.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeFlowSnapshot(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    since_seq: jlong,
    limit: jlong,
) -> jstring {
    let document = with_engine(&mut env, handle, Some("{}".to_string()), |engine| {
        let since = if since_seq <= 0 { 0 } else { since_seq as u64 };
        let cap = if limit <= 0 { 0 } else { limit as usize };
        Some(engine.flow_snapshot_json(since, cap))
    });
    answer(&env, document)
}

/// `resolveDomain(domain, ipv4)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeResolveDomain(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    domain: JString<'_>,
    ipv4: jboolean,
) -> jstring {
    let domain = text(&mut env, &domain);
    let document = with_engine(
        &mut env,
        handle,
        Some(crate::engine::resolve_domain_error_json("engine released")),
        |engine| Some(engine.block_on(engine.resolve_domain(&domain, ipv4 != 0))),
    );
    answer(&env, document)
}

// ---- callbacks ---------------------------------------------------------------------------------

/// `setBatchLogCallback(cb)`; a null clears it.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBatchLogCallback(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    if let Some(instance) = lookup_checked(&mut env, handle) {
        callbacks::set_sink(
            &mut env,
            &instance.engine,
            &instance.sink,
            callbacks::Slot::Batch,
            callback,
        );
    };
}

/// `setRaceLogCallback(cb)`; a null clears it.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetRaceLogCallback(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    if let Some(instance) = lookup_checked(&mut env, handle) {
        callbacks::set_sink(
            &mut env,
            &instance.engine,
            &instance.sink,
            callbacks::Slot::Race,
            callback,
        );
    };
}

/// `setBootstrapLogCallback(cb)`; a null clears it.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBootstrapLogCallback(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    if let Some(instance) = lookup_checked(&mut env, handle) {
        callbacks::set_sink(
            &mut env,
            &instance.engine,
            &instance.sink,
            callbacks::Slot::Bootstrap,
            callback,
        );
    };
}

// ---- stage 3: the TUN data plane ----------------------------------------------------------------

/// `startFull(fd)`: null on success, otherwise the error text (`StartFull` logged and returned).
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStartFull(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    fd: jlong,
) -> jstring {
    let error = with_engine(
        &mut env,
        handle,
        Some("engine released".to_string()),
        |engine| {
            let fd = i32::try_from(fd).unwrap_or(-1);
            engine.start_full(fd).err().map(|error| error.to_string())
        },
    );
    answer(&env, error)
}

/// `stopFull()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeStopFull(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.stop_full());
}

/// `releaseTun()`: the Go method closed the descriptor; here the fd belongs to the session, so this
/// is the same idempotent stop.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeReleaseTun(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) {
    with_engine(&mut env, handle, (), |engine| engine.stop_full());
}

/// `isFullRunning()`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeIsFullRunning(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
) -> jboolean {
    with_engine(&mut env, handle, 0, |engine| {
        u8::from(engine.is_full_running())
    })
}

/// `setSocketProtector(cb)`; a null clears it (server mode runs without one).
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetSocketProtector(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    let Some(instance) = lookup_checked(&mut env, handle) else {
        return;
    };
    if callback.is_null() {
        instance.engine.protector().clear();
        return;
    }
    if let Some(protector) = adapters::protector(&mut env, &callback) {
        instance.engine.protector().install(protector);
    } else {
        let _ = env.throw_new(
            "java/lang/IllegalStateException",
            "setSocketProtector: the callback could not be captured",
        );
    }
}

/// `setUIDResolver(cb)`; a null clears it.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetUidResolver(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    let Some(instance) = lookup_checked(&mut env, handle) else {
        return;
    };
    if callback.is_null() {
        instance.engine.attribution().clear_uid_resolver();
        return;
    }
    match adapters::JniUidResolver::new(&mut env, &callback) {
        Ok(resolver) => instance
            .engine
            .attribution()
            .install_uid_resolver(Arc::new(resolver)),
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "setUIDResolver: the callback could not be captured",
            );
        }
    }
}

/// `setAppUidResolver(cb)`; a null clears it.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetAppUidResolver(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    let Some(instance) = lookup_checked(&mut env, handle) else {
        return;
    };
    if callback.is_null() {
        instance.engine.attribution().clear_app_resolver();
        return;
    }
    match adapters::JniAppUidResolver::new(&mut env, &callback) {
        Ok(resolver) => instance
            .engine
            .attribution()
            .install_app_resolver(Arc::new(resolver)),
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "setAppUidResolver: the callback could not be captured",
            );
        }
    }
}

/// `setTrafficCallback(cb)`; a null stops the ticks.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetTrafficCallback(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    let Some(instance) = lookup_checked(&mut env, handle) else {
        return;
    };
    if callback.is_null() {
        instance.engine.set_traffic_sink(None);
        return;
    }
    match adapters::JniTrafficSink::new(&mut env, &callback) {
        Ok(sink) => instance.engine.set_traffic_sink(Some(Arc::new(sink))),
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "setTrafficCallback: the callback could not be captured",
            );
        }
    }
}

/// `setBlockedUIDs(csv)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockedUids(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    csv: JString<'_>,
) {
    let csv = text(&mut env, &csv);
    with_engine(&mut env, handle, (), |engine| engine.set_blocked_uids(&csv));
}

/// `setFilterHttp3(enabled)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetFilterHttp3(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    enabled: jboolean,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_filter_http3(enabled != 0)
    });
}

/// `setBlockEncryptedDns(enabled)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockEncryptedDns(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    enabled: jboolean,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_block_encrypted_dns(enabled != 0)
    });
}

/// `setBlockIpv6(enabled)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetBlockIpv6(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    enabled: jboolean,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_block_ipv6(enabled != 0)
    });
}

/// `setTickIntervalMs(ms)`
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetTickIntervalMs(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    millis: jlong,
) {
    with_engine(&mut env, handle, (), |engine| {
        engine.set_tick_interval_ms(millis)
    });
}

/// `configureOutboundProxy(json)`: null on success, otherwise the error text.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeConfigureOutboundProxy(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    payload: JString<'_>,
) -> jstring {
    let payload = text(&mut env, &payload);
    let error = with_engine(
        &mut env,
        handle,
        Some("engine released".to_string()),
        |engine| {
            let message = engine.configure_outbound_proxy(&payload);
            (!message.is_empty()).then_some(message)
        },
    );
    answer(&env, error)
}

/// `setOutboundProxyStatusCallback(cb)`; a null stops reporting.
#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_Engine_nativeSetOutboundProxyStatusCallback(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    handle: jlong,
    callback: JObject<'_>,
) {
    let Some(instance) = lookup_checked(&mut env, handle) else {
        return;
    };
    if callback.is_null() {
        instance.engine.set_outbound_status_sink(None);
        return;
    }
    match adapters::JniOutboundStatus::new(&mut env, &callback) {
        Ok(sink) => instance
            .engine
            .set_outbound_status_sink(Some(Arc::new(sink))),
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "setOutboundProxyStatusCallback: the callback could not be captured",
            );
        }
    }
}

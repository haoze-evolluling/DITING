//! The JNI side of the callbacks: the three Kotlin objects and the calls into them.
//!
//! The callbacks are stored as `GlobalRef`s inside an `Arc<CallbackSink>`, which is the engine's
//! [`EventSink`]. Calls arrive on the flusher thread (batch) and on tokio workers (race/bootstrap),
//! never on the JNI thread that installed them, so each call attaches the calling thread to the JVM
//! first; `attach_current_thread_permanently` keeps a long-lived worker attached instead of
//! re-attaching per row.
//!
//! Two rules keep the JVM environment clean:
//!
//! * a Java exception thrown by a callback is cleared after the call and reported as a failed call —
//!   leaving it pending would make the *next* JNI call fail with a confusing error;
//! * signature mismatches are the caller's problem, not the data path's: a null callback is a no-op.
//!
//! The signature strings are the gomobile-generated ones, copied verbatim in
//! [`BATCH_SIGNATURE`], [`RACE_SIGNATURE`] and [`BOOTSTRAP_SIGNATURE`]; the JVM smoke test declares
//! the same methods, so a typo fails the build rather than the device.

use std::sync::{Arc, Mutex};

use jni::objects::{GlobalRef, JObject, JValue};
use jni::{JNIEnv, JavaVM};

use crate::engine::Engine;
use crate::logs::{BootstrapEvent, EventSink, RaceEvent};

/// `BatchLogCallback.onDNSQueryBatch(String)`.
pub const BATCH_SIGNATURE: &str = "(Ljava/lang/String;)V";
/// `RaceLogCallback.onRaceResult(String, long, String, long, boolean, long, String, long, String,
/// long, boolean, boolean, String)`.
pub const RACE_SIGNATURE: &str = "(Ljava/lang/String;JLjava/lang/String;JZJLjava/lang/String;JLjava/lang/String;JZZLjava/lang/String;)V";
/// `BootstrapLogCallback.onBootstrapResult(String, String, String, String, boolean, long, boolean,
/// String)`.
pub const BOOTSTRAP_SIGNATURE: &str = "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZJZLjava/lang/String;)V";

/// Which callback is being installed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Slot {
    Batch,
    Race,
    Bootstrap,
}

/// The three Kotlin callback objects, plus the JVM they live in.
pub struct CallbackSink {
    vm: Option<JavaVM>,
    batch: Mutex<Option<GlobalRef>>,
    race: Mutex<Option<GlobalRef>>,
    bootstrap: Mutex<Option<GlobalRef>>,
}

impl CallbackSink {
    /// Captures the current JVM. `Err` when the entry point was not called from a JVM thread, which
    /// can only happen in a host test.
    pub fn new(env: &mut JNIEnv<'_>) -> Result<Self, jni::errors::Error> {
        let vm = env.get_java_vm()?;
        Ok(Self {
            vm: Some(vm),
            batch: Mutex::new(None),
            race: Mutex::new(None),
            bootstrap: Mutex::new(None),
        })
    }

    /// A sink with no JVM, for host tests that only exercise the engine.
    pub fn headless() -> Self {
        Self {
            vm: None,
            batch: Mutex::new(None),
            race: Mutex::new(None),
            bootstrap: Mutex::new(None),
        }
    }

    pub fn set(&self, env: &mut JNIEnv<'_>, slot: Slot, callback: JObject<'_>) {
        let target = match slot {
            Slot::Batch => &self.batch,
            Slot::Race => &self.race,
            Slot::Bootstrap => &self.bootstrap,
        };
        let mut current = target.lock().unwrap_or_else(|error| error.into_inner());
        if callback.is_null() {
            *current = None;
            return;
        }
        *current = env.new_global_ref(&callback).ok();
    }

    /// True when a batch callback is installed: rows are only queued while one is.
    pub fn has_batch(&self) -> bool {
        self.batch
            .lock()
            .map(|slot| slot.is_some())
            .unwrap_or(false)
    }

    fn reference(&self, slot: Slot) -> Option<GlobalRef> {
        let target = match slot {
            Slot::Batch => &self.batch,
            Slot::Race => &self.race,
            Slot::Bootstrap => &self.bootstrap,
        };
        target
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// Attaches the calling thread, runs `call`, then clears any Java exception it left behind.
    fn with_env(&self, call: impl FnOnce(&mut JNIEnv<'_>) -> Option<()>) -> Option<()> {
        let vm = self.vm.as_ref()?;
        let mut env = vm.attach_current_thread_permanently().ok()?;
        let result = call(&mut env);
        if env.exception_check().unwrap_or(false) {
            let _ = env.exception_clear();
        }
        result
    }

    fn call_string(&self, slot: Slot, method: &str, signature: &str, payload: &str) {
        let Some(target) = self.reference(slot) else {
            return;
        };
        self.with_env(|env| {
            let text = env.new_string(payload).ok()?;
            let text = JObject::from(text);
            env.call_method(target.as_obj(), method, signature, &[JValue::Object(&text)])
                .ok()?;
            Some(())
        });
    }
}

impl EventSink for CallbackSink {
    fn batch(&self, json: &str) {
        self.call_string(Slot::Batch, "onDNSQueryBatch", BATCH_SIGNATURE, json);
    }

    fn race(&self, event: &RaceEvent) {
        let Some(target) = self.reference(Slot::Race) else {
            return;
        };
        self.with_env(|env| {
            let query_name = JObject::from(env.new_string(&event.query_name).ok()?);
            let strategy = JObject::from(env.new_string(&event.strategy).ok()?);
            let selected = JObject::from(env.new_string(&event.selected_provider_id).ok()?);
            let winner = JObject::from(env.new_string(&event.winner_provider_id).ok()?);
            let error = JObject::from(env.new_string(&event.error_message).ok()?);
            let arguments = [
                JValue::Object(&query_name),
                JValue::Long(event.query_type as i64),
                JValue::Object(&strategy),
                JValue::Long(event.provider_count),
                JValue::Bool(u8::from(event.success)),
                JValue::Long(event.elapsed_ms),
                JValue::Object(&selected),
                JValue::Long(event.selected_elapsed_ms),
                JValue::Object(&winner),
                JValue::Long(event.winner_elapsed_ms),
                JValue::Bool(u8::from(event.fallback_used)),
                JValue::Bool(u8::from(event.fallback_success)),
                JValue::Object(&error),
            ];
            env.call_method(target.as_obj(), "onRaceResult", RACE_SIGNATURE, &arguments)
                .ok()?;
            Some(())
        });
    }

    fn bootstrap(&self, event: &BootstrapEvent) {
        let Some(target) = self.reference(Slot::Bootstrap) else {
            return;
        };
        self.with_env(|env| {
            let id = JObject::from(env.new_string(&event.ip_id).ok()?);
            let name = JObject::from(env.new_string(&event.ip_name).ok()?);
            let ip = JObject::from(env.new_string(&event.ip).ok()?);
            let host = JObject::from(env.new_string(&event.host).ok()?);
            let error = JObject::from(env.new_string(&event.error_message).ok()?);
            let arguments = [
                JValue::Object(&id),
                JValue::Object(&name),
                JValue::Object(&ip),
                JValue::Object(&host),
                JValue::Bool(u8::from(event.success)),
                JValue::Long(event.elapsed_ms),
                JValue::Bool(u8::from(event.fallback_used)),
                JValue::Object(&error),
            ];
            env.call_method(
                target.as_obj(),
                "onBootstrapResult",
                BOOTSTRAP_SIGNATURE,
                &arguments,
            )
            .ok()?;
            Some(())
        });
    }
}

/// Installs or clears one callback on the engine, and keeps the batch callback's presence in sync
/// with the log buffer (rows are only queued while a batch callback exists).
pub fn set_sink(
    env: &mut JNIEnv<'_>,
    engine: &Arc<Engine>,
    sink: &Arc<CallbackSink>,
    slot: Slot,
    callback: JObject<'_>,
) {
    sink.set(env, slot, callback);
    if slot == Slot::Batch {
        if sink.has_batch() {
            engine.set_event_sink(Some(sink.clone()));
        } else {
            engine.set_event_sink(None);
        }
    }
}

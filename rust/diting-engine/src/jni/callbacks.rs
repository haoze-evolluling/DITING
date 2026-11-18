//! The JNI side of the callbacks: the three Kotlin objects and the calls into them.
//!
//! The callbacks are stored as `GlobalRef`s inside an `Arc<CallbackSink>`, which is the engine's
//! [`EventSink`]. Calls never arrive on the JNI thread that installed them: the DNS batch comes
//! from the engine's log flusher, and race/bootstrap events are folded into one packed batch by a
//! dedicated thread here. Each thread attaches to the JVM once
//! (`attach_current_thread_permanently`) instead of re-attaching per row.
//!
//! Race and bootstrap results used to cross the boundary one at a time, with five and eight
//! arguments (most of them fresh Java strings). Under `smart_prediction` the race log fires for
//! every upstream resolution, so that was dozens of crossings per page load. Both are now appended
//! to a bounded channel and handed over as one `byte[]` per batch, in the layouts
//! [`crate::logs::race_batch_payload`] and [`crate::logs::bootstrap_batch_payload`] spell.
//!
//! Two rules keep the JVM environment clean:
//!
//! * a Java exception thrown by a callback is cleared after the call and reported as a failed call —
//!   leaving it pending would make the *next* JNI call fail with a confusing error;
//! * signature mismatches are the caller's problem, not the data path's: a null callback is a no-op.
//!
//! The signature strings are copied verbatim from the Kotlin interfaces; the JVM smoke test declares
//! the same methods, so a typo fails the build rather than the device.

use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use jni::objects::{GlobalRef, JObject, JValue};
use jni::{JNIEnv, JavaVM};

use crate::engine::Engine;
use crate::logs::{
    bootstrap_batch_payload, race_batch_payload, BootstrapEvent, EventSink, RaceEvent,
};

/// `BatchLogCallback.onDNSQueryBatch(byte[])`.
pub const BATCH_SIGNATURE: &str = "([B)V";
/// `RaceLogCallback.onRaceEvents(byte[])`.
pub const RACE_BATCH_SIGNATURE: &str = "([B)V";
/// `BootstrapLogCallback.onBootstrapEvents(byte[])`.
pub const BOOTSTRAP_BATCH_SIGNATURE: &str = "([B)V";

/// Events one race/bootstrap batch may carry before the flusher hands them over.
const EVENT_BATCH_SIZE: usize = 64;
/// How long a partial race/bootstrap batch waits for more events.
const EVENT_FLUSH_INTERVAL: Duration = Duration::from_millis(200);
/// Events the event holders may buffer ahead of the flusher before rows start being dropped.
const EVENT_CHANNEL_CAPACITY: usize = 1_024;

/// Which callback is being installed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Slot {
    Batch,
    Race,
    Bootstrap,
}

/// One buffered race/bootstrap result, or a request to deliver them now (teardown).
enum Pending {
    Race(RaceEvent),
    Bootstrap(BootstrapEvent),
    Flush(Sender<()>),
}

/// A callback slot the flusher thread reads while Kotlin installs or clears it.
type SlotRef = Arc<Mutex<Option<GlobalRef>>>;

/// The three Kotlin callback objects, plus the JVM they live in.
pub struct CallbackSink {
    vm: Option<Arc<JavaVM>>,
    batch: Mutex<Option<GlobalRef>>,
    race: SlotRef,
    bootstrap: SlotRef,
    events: Option<SyncSender<Pending>>,
    flusher: Mutex<Option<JoinHandle<()>>>,
}

impl CallbackSink {
    /// Captures the current JVM. `Err` when the entry point was not called from a JVM thread, which
    /// can only happen in a host test.
    pub fn new(env: &mut JNIEnv<'_>) -> Result<Self, jni::errors::Error> {
        let vm = Arc::new(env.get_java_vm()?);
        let race: SlotRef = Arc::new(Mutex::new(None));
        let bootstrap: SlotRef = Arc::new(Mutex::new(None));
        let (sender, receiver) = mpsc::sync_channel(EVENT_CHANNEL_CAPACITY);
        let flusher = {
            let vm = vm.clone();
            let race = race.clone();
            let bootstrap = bootstrap.clone();
            thread::Builder::new()
                .name("diting-engine-events".to_string())
                .spawn(move || flush_events(&vm, &race, &bootstrap, receiver))
                .map_err(|_| jni::errors::Error::JniCall(jni::errors::JniError::Unknown))?
        };
        Ok(Self {
            vm: Some(vm),
            batch: Mutex::new(None),
            race,
            bootstrap,
            events: Some(sender),
            flusher: Mutex::new(Some(flusher)),
        })
    }

    /// A sink with no JVM, for host tests that only exercise the engine.
    pub fn headless() -> Self {
        Self {
            vm: None,
            batch: Mutex::new(None),
            race: Arc::new(Mutex::new(None)),
            bootstrap: Arc::new(Mutex::new(None)),
            events: None,
            flusher: Mutex::new(None),
        }
    }

    pub fn set(&self, env: &mut JNIEnv<'_>, slot: Slot, callback: JObject<'_>) {
        let mut current = match slot {
            Slot::Batch => self.batch.lock().unwrap_or_else(|error| error.into_inner()),
            Slot::Race => self.race.lock().unwrap_or_else(|error| error.into_inner()),
            Slot::Bootstrap => self
                .bootstrap
                .lock()
                .unwrap_or_else(|error| error.into_inner()),
        };
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

    /// True when any of the three callbacks is installed.
    pub fn has_any(&self) -> bool {
        self.has_batch()
            || self.slot_ref(&self.race).is_some()
            || self.slot_ref(&self.bootstrap).is_some()
    }

    fn slot_ref(&self, slot: &SlotRef) -> Option<GlobalRef> {
        slot.lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    fn call_bytes(&self, slot: Slot, method: &str, signature: &str, payload: &[u8]) {
        let target = match slot {
            Slot::Batch => self
                .batch
                .lock()
                .ok()
                .and_then(|slot| slot.as_ref().cloned()),
            Slot::Race => self.slot_ref(&self.race),
            Slot::Bootstrap => self.slot_ref(&self.bootstrap),
        };
        let (Some(target), Some(vm)) = (target, self.vm.as_ref()) else {
            return;
        };
        deliver_bytes(vm, &target, method, signature, payload);
    }
}

impl EventSink for CallbackSink {
    fn batch(&self, payload: &[u8]) {
        self.call_bytes(Slot::Batch, "onDNSQueryBatch", BATCH_SIGNATURE, payload);
    }

    fn race(&self, event: RaceEvent) {
        let Some(sender) = &self.events else {
            return;
        };
        // A full channel drops the row rather than stalling the DNS worker.
        let _ = sender.try_send(Pending::Race(event));
    }

    fn bootstrap(&self, event: BootstrapEvent) {
        let Some(sender) = &self.events else {
            return;
        };
        let _ = sender.try_send(Pending::Bootstrap(event));
    }

    fn wants_batch(&self) -> bool {
        self.has_batch()
    }

    fn flush(&self) {
        let Some(sender) = &self.events else {
            return;
        };
        // Blocking send: the flusher drains in order, so the marker is reached after every event
        // already queued. The ack lets teardown wait for the delivery instead of racing it.
        let (ack, wait) = mpsc::channel();
        // Bounded enqueue: the flusher is the only consumer and it may be parked inside a Kotlin
        // callback, so an unconditional `send` could hang teardown on the JNI thread forever.
        let deadline = Instant::now() + EVENT_FLUSH_INTERVAL * 25;
        let mut marker = Pending::Flush(ack);
        loop {
            match sender.try_send(marker) {
                Ok(()) => {
                    let _ = wait.recv_timeout(EVENT_FLUSH_INTERVAL * 25);
                    return;
                }
                Err(mpsc::TrySendError::Full(returned)) => {
                    if Instant::now() >= deadline {
                        // Give up: the queued events are still delivered by the flusher's timer.
                        return;
                    }
                    marker = returned;
                    thread::sleep(Duration::from_millis(1));
                }
                Err(mpsc::TrySendError::Disconnected(_)) => return,
            }
        }
    }
}

impl Drop for CallbackSink {
    fn drop(&mut self) {
        // Closing the channel ends the flusher after its final batch.
        self.events.take();
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

/// Drains the race/bootstrap channel in batches and hands each stream to Kotlin.
fn flush_events(
    vm: &JavaVM,
    race_slot: &SlotRef,
    bootstrap_slot: &SlotRef,
    receiver: Receiver<Pending>,
) {
    let mut races: Vec<RaceEvent> = Vec::new();
    let mut bootstraps: Vec<BootstrapEvent> = Vec::new();
    // Block until the first event of a batch, then drain everything already queued.
    loop {
        let mut ack: Option<Sender<()>> = None;
        match receiver.recv() {
            Ok(Pending::Flush(sender)) => ack = Some(sender),
            Ok(event) => push_pending(event, &mut races, &mut bootstraps),
            Err(_) => break,
        }
        let deadline = Instant::now() + EVENT_FLUSH_INTERVAL;
        while ack.is_none() && races.len() + bootstraps.len() < EVENT_BATCH_SIZE {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                break;
            }
            match receiver.recv_timeout(remaining) {
                Ok(Pending::Flush(sender)) => ack = Some(sender),
                Ok(event) => push_pending(event, &mut races, &mut bootstraps),
                Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => break,
            }
        }
        if !races.is_empty() {
            if let Some(target) = reference(race_slot) {
                deliver_bytes(
                    vm,
                    &target,
                    "onRaceEvents",
                    RACE_BATCH_SIGNATURE,
                    &race_batch_payload(&races),
                );
            }
            races.clear();
        }
        if !bootstraps.is_empty() {
            if let Some(target) = reference(bootstrap_slot) {
                deliver_bytes(
                    vm,
                    &target,
                    "onBootstrapEvents",
                    BOOTSTRAP_BATCH_SIGNATURE,
                    &bootstrap_batch_payload(&bootstraps),
                );
            }
            bootstraps.clear();
        }
        if let Some(sender) = ack {
            let _ = sender.send(());
        }
    }
}

fn push_pending(event: Pending, races: &mut Vec<RaceEvent>, bootstraps: &mut Vec<BootstrapEvent>) {
    match event {
        Pending::Race(event) => races.push(event),
        Pending::Bootstrap(event) => bootstraps.push(event),
        // The flusher handles a flush marker before calling this.
        Pending::Flush(_) => {}
    }
}

fn reference(slot: &SlotRef) -> Option<GlobalRef> {
    slot.lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone()
}

/// Attaches the calling thread, makes one `byte[]` call, then clears a Java exception.
fn deliver_bytes(vm: &JavaVM, target: &GlobalRef, method: &str, signature: &str, payload: &[u8]) {
    let Ok(mut env) = vm.attach_current_thread_permanently() else {
        return;
    };
    {
        let rows = env.byte_array_from_slice(payload);
        if let Ok(rows) = rows {
            let rows = JObject::from(rows);
            let _ = env.call_method(target.as_obj(), method, signature, &[JValue::Object(&rows)]);
        }
    }
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
}

/// Installs or clears one callback on the engine and keeps the sink installed while any callback
/// remains (race/bootstrap events are buffered by the sink, not by the DNS log buffer).
pub fn set_sink(
    env: &mut JNIEnv<'_>,
    engine: &Arc<Engine>,
    sink: &Arc<CallbackSink>,
    slot: Slot,
    callback: JObject<'_>,
) {
    sink.set(env, slot, callback);
    if sink.has_any() {
        engine.set_event_sink(Some(sink.clone()));
    } else {
        engine.set_event_sink(None);
    }
}

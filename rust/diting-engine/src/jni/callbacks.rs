use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use jni::objects::{Global, JObject, JValue};
use jni::signature::MethodSignature;
use jni::strings::JNIStr;
use jni::{Env, JavaVM};

use crate::engine::Engine;
use crate::logs::{
    bootstrap_batch_payload, race_batch_payload, BootstrapEvent, EventSink, RaceEvent,
};

const EVENT_BATCH_SIZE: usize = 64;
const EVENT_FLUSH_INTERVAL: Duration = Duration::from_millis(200);
const EVENT_CHANNEL_CAPACITY: usize = 1_024;

type GlobalObject = Global<JObject<'static>>;
type SharedGlobal = Arc<GlobalObject>;
type SlotRef = Arc<Mutex<Option<SharedGlobal>>>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Slot {
    Batch,
    Race,
    Bootstrap,
}

enum Pending {
    Race(RaceEvent),
    Bootstrap(BootstrapEvent),
    Flush(Sender<()>),
}

#[derive(Clone, Copy)]
enum CallbackMethod {
    Batch,
    Race,
    Bootstrap,
}

impl CallbackMethod {
    fn name(self) -> &'static JNIStr {
        match self {
            CallbackMethod::Batch => jni::jni_str!("onDNSQueryBatch"),
            CallbackMethod::Race => jni::jni_str!("onRaceEvents"),
            CallbackMethod::Bootstrap => jni::jni_str!("onBootstrapEvents"),
        }
    }

    fn signature(self) -> MethodSignature<'static, 'static> {
        match self {
            CallbackMethod::Batch => jni::jni_sig!("([B)V"),
            CallbackMethod::Race => jni::jni_sig!("([B)V"),
            CallbackMethod::Bootstrap => jni::jni_sig!("([B)V"),
        }
    }
}

pub struct CallbackSink {
    vm: Option<Arc<JavaVM>>,
    batch: Mutex<Option<SharedGlobal>>,
    race: SlotRef,
    bootstrap: SlotRef,
    events: Option<SyncSender<Pending>>,
    flusher: Mutex<Option<JoinHandle<()>>>,
}

impl CallbackSink {
    pub fn new(env: &mut Env<'_>) -> Result<Self, jni::errors::Error> {
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

    pub fn set(&self, env: &mut Env<'_>, slot: Slot, callback: JObject<'_>) {
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
        *current = env.new_global_ref(&callback).ok().map(Arc::new);
    }

    pub fn has_batch(&self) -> bool {
        self.batch
            .lock()
            .map(|slot| slot.is_some())
            .unwrap_or(false)
    }

    pub fn has_any(&self) -> bool {
        self.has_batch()
            || self.slot_ref(&self.race).is_some()
            || self.slot_ref(&self.bootstrap).is_some()
    }

    fn slot_ref(&self, slot: &SlotRef) -> Option<SharedGlobal> {
        slot.lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    fn call_bytes(&self, slot: Slot, method: CallbackMethod, payload: &[u8]) {
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
        deliver_bytes(vm, &target, method, payload);
    }
}

impl EventSink for CallbackSink {
    fn batch(&self, payload: &[u8]) {
        self.call_bytes(Slot::Batch, CallbackMethod::Batch, payload);
    }

    fn race(&self, event: RaceEvent) {
        let Some(sender) = &self.events else {
            return;
        };
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
        let (ack, wait) = mpsc::channel();
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

fn flush_events(
    vm: &JavaVM,
    race_slot: &SlotRef,
    bootstrap_slot: &SlotRef,
    receiver: Receiver<Pending>,
) {
    let mut races: Vec<RaceEvent> = Vec::new();
    let mut bootstraps: Vec<BootstrapEvent> = Vec::new();
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
                    CallbackMethod::Race,
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
                    CallbackMethod::Bootstrap,
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
        Pending::Flush(_) => {}
    }
}

fn reference(slot: &SlotRef) -> Option<SharedGlobal> {
    slot.lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone()
}

fn deliver_bytes(vm: &JavaVM, target: &GlobalObject, method: CallbackMethod, payload: &[u8]) {
    let _ = vm.attach_current_thread(|env| -> Result<(), jni::errors::Error> {
        let rows = env.byte_array_from_slice(payload)?;
        let rows = JObject::from(rows);
        let _ = env.call_method(
            target.as_obj(),
            method.name(),
            method.signature(),
            &[JValue::Object(&rows)],
        );
        if env.exception_check() {
            let _ = env.exception_clear();
        }
        Ok(())
    });
}

pub fn set_sink(
    env: &mut Env<'_>,
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

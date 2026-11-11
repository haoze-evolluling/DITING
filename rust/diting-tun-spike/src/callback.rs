//! The callback thread: every Kotlin callback is delivered from one dedicated thread.
//!
//! The Go engine called `BatchLogCallback.onDNSQueryBatch` from whichever goroutine had a batch ready,
//! and gomobile attached that goroutine to the JVM on the way in. Under Rust the producer is a tokio
//! worker or, here, the TUN worker thread; letting those threads into the JVM would mean an
//! attach/detach (or a permanently attached foreign worker) on the data path, and a slow Kotlin
//! callback would stall packet processing.
//!
//! So the data plane only ever does `try_send`: one named thread owns the JVM attachment, drains the
//! queue, and calls Java. Three properties fall out of that and each one is tested:
//!
//! * **one thread** — the JVM sees every callback from the same thread, which is what makes Kotlin
//!   callbacks safe to write without extra synchronisation (the app's log writer assumes it);
//! * **bounded** — a full queue drops the payload and counts it instead of blocking the TUN worker;
//! * **isolated** — a panic in the handler is caught, so one bad callback cannot take the thread down
//!   and silently stop all future logging.
//!
//! The handler is created *on* the new thread (`factory`), which is where the JNI adapter attaches to
//! the JVM once for the thread's lifetime.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

/// What the callback thread did so far.
#[derive(Debug, Clone, Default)]
pub struct CallbackStats {
    pub delivered: u64,
    pub dropped: u64,
    pub panics: u64,
    /// The name the JVM will see (`Thread.currentThread().getName()`).
    pub thread: String,
}

/// One queue, one thread, one handler.
pub struct Dispatcher {
    name: String,
    tx: Mutex<Option<SyncSender<String>>>,
    join: Mutex<Option<JoinHandle<()>>>,
    delivered: Arc<AtomicU64>,
    dropped: Arc<AtomicU64>,
    panics: Arc<AtomicU64>,
}

impl Dispatcher {
    /// Spawns the callback thread.
    ///
    /// `factory` runs on the new thread before the first payload, so the JNI adapter can attach there
    /// exactly once; `capacity` is how many payloads may be queued before [`Dispatcher::dispatch`]
    /// starts dropping.
    pub fn spawn<F>(
        name: &str,
        capacity: usize,
        factory: impl FnOnce() -> F + Send + 'static,
    ) -> Result<Arc<Dispatcher>, String>
    where
        F: FnMut(&str) + Send + 'static,
    {
        let (tx, rx) = sync_channel::<String>(capacity.max(1));
        let delivered = Arc::new(AtomicU64::new(0));
        let dropped = Arc::new(AtomicU64::new(0));
        let panics = Arc::new(AtomicU64::new(0));
        let counters = (delivered.clone(), panics.clone());

        let join = std::thread::Builder::new()
            .name(name.to_string())
            .spawn(move || run(&rx, factory, counters))
            .map_err(|err| format!("spawn the callback thread '{name}': {err}"))?;

        Ok(Arc::new(Dispatcher {
            name: name.to_string(),
            tx: Mutex::new(Some(tx)),
            join: Mutex::new(Some(join)),
            delivered,
            dropped,
            panics,
        }))
    }

    /// Queues one payload. `false` means the queue was full and the payload was dropped.
    pub fn dispatch(&self, payload: String) -> bool {
        let sender = self
            .tx
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .clone();
        let Some(sender) = sender else {
            self.dropped.fetch_add(1, Ordering::SeqCst);
            return false;
        };
        match sender.try_send(payload) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) => {
                self.dropped.fetch_add(1, Ordering::SeqCst);
                false
            }
            Err(TrySendError::Disconnected(_)) => {
                self.dropped.fetch_add(1, Ordering::SeqCst);
                false
            }
        }
    }

    /// Closes the queue and waits for the thread. Idempotent.
    pub fn stop(&self) {
        self.tx.lock().unwrap_or_else(|err| err.into_inner()).take();
        let handle = self
            .join
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .take();
        if let Some(handle) = handle {
            let _ = handle.join();
        }
    }

    pub fn stats(&self) -> CallbackStats {
        CallbackStats {
            delivered: self.delivered.load(Ordering::SeqCst),
            dropped: self.dropped.load(Ordering::SeqCst),
            panics: self.panics.load(Ordering::SeqCst),
            thread: self.name.clone(),
        }
    }
}

impl Drop for Dispatcher {
    fn drop(&mut self) {
        self.stop();
    }
}

fn run<F>(
    queue: &Receiver<String>,
    factory: impl FnOnce() -> F,
    counters: (Arc<AtomicU64>, Arc<AtomicU64>),
) where
    F: FnMut(&str),
{
    let (delivered, panics) = counters;
    // On the callback thread: the JNI adapter attaches to the JVM here, once.
    let mut handler = factory();
    while let Ok(payload) = queue.recv() {
        // A panicking callback must not end the thread: the app would lose every later log line with
        // no diagnostic at all.
        match catch_unwind(AssertUnwindSafe(|| handler(&payload))) {
            Ok(()) => {
                delivered.fetch_add(1, Ordering::SeqCst);
            }
            Err(_) => {
                panics.fetch_add(1, Ordering::SeqCst);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::sync::Mutex as StdMutex;
    use std::thread::ThreadId;
    use std::time::{Duration, Instant};

    fn wait_for(dispatcher: &Arc<Dispatcher>, delivered: u64) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while dispatcher.stats().delivered < delivered {
            assert!(Instant::now() < deadline, "callbacks never arrived");
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn every_payload_arrives_on_the_one_callback_thread() {
        let threads = Arc::new(StdMutex::new(Vec::<ThreadId>::new()));
        let seen = Arc::new(AtomicUsize::new(0));
        let recorded = threads.clone();
        let counter = seen.clone();
        let dispatcher = Dispatcher::spawn("diting-test-callback", 512, move || {
            move |_payload: &str| {
                recorded
                    .lock()
                    .unwrap_or_else(|err| err.into_inner())
                    .push(std::thread::current().id());
                counter.fetch_add(1, Ordering::SeqCst);
            }
        })
        .expect("spawn");

        // Produce from several threads, the way tokio workers would.
        let producers: Vec<_> = (0..4)
            .map(|index| {
                let dispatcher = dispatcher.clone();
                std::thread::spawn(move || {
                    for row in 0..250 {
                        dispatcher.dispatch(format!("{index}-{row}"));
                    }
                })
            })
            .collect();
        for producer in producers {
            producer.join().expect("producer");
        }
        wait_for(&dispatcher, 1000);

        // Copy the thread ids out and release the lock: the handler takes it too, and holding it
        // across `stop` would deadlock the join below.
        let observed: Vec<ThreadId> = {
            let threads = threads.lock().unwrap_or_else(|err| err.into_inner());
            threads.clone()
        };
        assert_eq!(observed.len(), 1000, "no payload was lost");
        assert!(
            observed.windows(2).all(|pair| pair[0] == pair[1]),
            "all callbacks arrive on one thread"
        );
        assert!(
            dispatcher.dispatch("after".to_string()),
            "the queue still accepts payloads"
        );
        dispatcher.stop();
        assert_eq!(dispatcher.stats().thread, "diting-test-callback");
    }

    #[test]
    fn a_full_queue_drops_and_counts_instead_of_blocking_the_producer() {
        // Nothing drains the queue while the gate is shut, so one payload has to be dropped.
        let gate = Arc::new((StdMutex::new(false), std::sync::Condvar::new()));
        let waiting = gate.clone();
        let dispatcher = Dispatcher::spawn("diting-test-full", 1, move || {
            let (lock, ready) = &*waiting;
            let mut open = lock.lock().unwrap_or_else(|err| err.into_inner());
            while !*open {
                open = ready.wait(open).unwrap_or_else(|err| err.into_inner());
            }
            |_payload: &str| {}
        })
        .expect("spawn");

        assert!(dispatcher.dispatch("first".to_string()));
        // The handler is still parked, so the queue (capacity 1) is full.
        let started = Instant::now();
        assert!(!dispatcher.dispatch("second".to_string()));
        assert!(
            started.elapsed() < Duration::from_millis(500),
            "dispatch must not block the data plane"
        );
        assert_eq!(dispatcher.stats().dropped, 1);

        // Let the handler out, then let the first payload be delivered.
        let (lock, ready) = &*gate;
        *lock.lock().unwrap_or_else(|err| err.into_inner()) = true;
        ready.notify_all();
        wait_for(&dispatcher, 1);
        dispatcher.stop();
    }

    #[test]
    fn a_panicking_callback_does_not_stop_later_payloads() {
        let seen = Arc::new(AtomicUsize::new(0));
        let counter = seen.clone();
        let dispatcher = Dispatcher::spawn("diting-test-panic", 8, move || {
            move |_payload: &str| {
                if counter.fetch_add(1, Ordering::SeqCst) == 0 {
                    panic!("the Kotlin callback threw");
                }
            }
        })
        .expect("spawn");

        for row in 0..3 {
            dispatcher.dispatch(format!("row-{row}"));
        }
        let deadline = Instant::now() + Duration::from_secs(5);
        while seen.load(Ordering::SeqCst) < 3 {
            assert!(Instant::now() < deadline, "the thread died with the panic");
            std::thread::sleep(Duration::from_millis(5));
        }
        dispatcher.stop();
        assert_eq!(dispatcher.stats().panics, 1);
        assert_eq!(dispatcher.stats().delivered, 2);
    }

    #[test]
    fn dispatch_after_stop_is_a_counted_drop() {
        let dispatcher =
            Dispatcher::spawn("diting-test-stopped", 4, || |_payload: &str| {}).expect("spawn");
        dispatcher.stop();
        assert!(!dispatcher.dispatch("late".to_string()));
        assert_eq!(dispatcher.stats().dropped, 1);
    }
}

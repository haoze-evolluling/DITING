//! The batch DNS log, the race log and the bootstrap log.
//!
//! `log_aggregator.go` kept three things around the Rust buffer: the flush goroutine and its
//! lazily-armed 100 ms timer, the `encoding/json` of a drained batch, and the Kotlin callback. That
//! is what [`Logs`] is: the buffer is [`diting_telemetry_core::LogAggregator`] (2048 slots, the 3/4
//! high-water shed, the two drop counters), and everything around it is here.
//!
//! # Flush behaviour
//!
//! Identical to the Go loop, because it is a battery decision, not a taste one: complete batches of
//! [`BATCH_SIZE`] go out immediately, a partial tail waits up to [`FLUSH_INTERVAL`], and the timer
//! is only armed while rows are pending. An idle engine therefore parks the thread instead of
//! waking it ten times a second.
//!
//! # Threads
//!
//! One dedicated flusher thread per engine, owned by [`Logs`] and stopped when the engine is freed.
//! The JNI implementation of [`EventSink`] attaches to the JVM once per thread (the flusher) instead
//! of attaching on every row, and it clears any pending Java exception, so a Kotlin callback that
//! throws cannot leave the JNI environment poisoned for the next call.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, RwLock};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use diting_telemetry_core::{LogAggregator, LogItem, PushOutcome};

/// `logBatchSize`.
pub const BATCH_SIZE: usize = 50;
/// `logFlushInterval`.
pub const FLUSH_INTERVAL: Duration = Duration::from_millis(100);

/// One finished query race, as `RaceLogWriter.write` receives it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RaceEvent {
    pub query_name: String,
    pub query_type: u16,
    pub strategy: String,
    pub provider_count: i64,
    pub success: bool,
    pub elapsed_ms: i64,
    pub selected_provider_id: String,
    pub selected_elapsed_ms: i64,
    pub winner_provider_id: String,
    pub winner_elapsed_ms: i64,
    pub fallback_used: bool,
    pub fallback_success: bool,
    pub error_message: String,
}

/// One bootstrap (encrypted-upstream dial) result.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BootstrapEvent {
    pub ip_id: String,
    pub ip_name: String,
    pub ip: String,
    pub host: String,
    pub success: bool,
    pub elapsed_ms: i64,
    pub fallback_used: bool,
    pub error_message: String,
}

/// The bootstrap log a resolver transport fires while it dials.
///
/// The upstream resolver owns no log buffer; the engine's [`Logs`] does, so the resolver only gets
/// this narrow view of it. A test recorder implements the same one method.
pub trait BootstrapSink: Send + Sync {
    /// `BootstrapLogCallback.onBootstrapResult`.
    fn bootstrap(&self, event: &BootstrapEvent);
}

/// What the engine reports to the app.
///
/// Both implementations are cheap and non-blocking on the caller's thread: the JNI one posts to the
/// Kotlin object from the flusher thread, a test one just records.
pub trait EventSink: Send + Sync {
    /// `BatchLogCallback.onDNSQueryBatch`: one JSON array of `d`/`b`/`t`/… rows.
    fn batch(&self, json: &str);
    /// `RaceLogCallback.onRaceResult`.
    fn race(&self, event: &RaceEvent);
    /// `BootstrapLogCallback.onBootstrapResult`.
    fn bootstrap(&self, event: &BootstrapEvent);
}

/// The engine's log plumbing: the buffer, the flusher thread and the current sink.
pub struct Logs {
    aggregator: Arc<LogAggregator>,
    sink: Arc<RwLock<Option<Arc<dyn EventSink>>>>,
    wake: Sender<Wake>,
    stopped: Arc<AtomicBool>,
    flusher: Option<JoinHandle<()>>,
}

enum Wake {
    Rows,
    Stop,
}

impl Logs {
    /// Starts the flusher. The thread exits when [`Logs`] is dropped or [`Logs::stop`] runs.
    pub fn new() -> Self {
        let aggregator = Arc::new(LogAggregator::new());
        let (wake, receiver) = mpsc::channel();
        let stopped = Arc::new(AtomicBool::new(false));
        // The sink is installed later (Kotlin calls `setBatchLogCallback` after the config), so the
        // flusher reads it through this shared cell instead of capturing one value.
        let sink: Arc<RwLock<Option<Arc<dyn EventSink>>>> = Arc::new(RwLock::new(None));
        let flusher = {
            let aggregator = aggregator.clone();
            let sink = sink.clone();
            let stopped = stopped.clone();
            thread::Builder::new()
                .name("diting-engine-logs".to_string())
                .spawn(move || flush_loop(aggregator, sink, receiver, stopped))
                .expect("the log flusher thread must start")
        };
        Self {
            aggregator,
            sink,
            wake,
            stopped,
            flusher: Some(flusher),
        }
    }

    /// Posts one row, mirroring `notifyLog`'s "batch callback first, then the single callback".
    pub fn push(&self, item: LogItem) {
        if self.sink.read().map(|sink| sink.is_none()).unwrap_or(true) {
            return;
        }
        if self.aggregator.push(item) == PushOutcome::Dropped {
            return;
        }
        let _ = self.wake.send(Wake::Rows);
    }

    pub fn has_sink(&self) -> bool {
        self.sink.read().map(|sink| sink.is_some()).unwrap_or(false)
    }

    /// Installs (or replaces) the sink. Null on the Kotlin side clears it.
    pub fn set_sink(&self, sink: Option<Arc<dyn EventSink>>) {
        if let Ok(mut current) = self.sink.write() {
            *current = sink;
        }
    }

    pub fn dropped(&self) -> u64 {
        self.aggregator.dropped()
    }

    pub fn pending(&self) -> usize {
        self.aggregator.pending()
    }

    pub fn race(&self, event: RaceEvent) {
        let sink = self.sink.read().ok().and_then(|sink| sink.clone());
        if let Some(sink) = sink {
            sink.race(&event);
        }
    }

    pub fn bootstrap(&self, event: BootstrapEvent) {
        let sink = self.sink.read().ok().and_then(|sink| sink.clone());
        if let Some(sink) = sink {
            sink.bootstrap(&event);
        }
    }
}

impl BootstrapSink for Logs {
    fn bootstrap(&self, event: &BootstrapEvent) {
        Logs::bootstrap(self, event.clone());
    }
}

/// A sink for the resolvers that have no engine behind them (the default configuration and the
/// transport tests): the event is dropped instead of buffered.
#[derive(Debug, Default)]
pub struct DiscardBootstrapSink;

impl BootstrapSink for DiscardBootstrapSink {
    fn bootstrap(&self, _event: &BootstrapEvent) {}
}

impl Logs {
    /// Drains everything left, then stops the thread (`logAggregator.stop`).
    pub fn stop(&mut self) {
        if self.flusher.is_none() {
            return;
        }
        self.stopped.store(true, Ordering::Release);
        let _ = self.wake.send(Wake::Stop);
        if let Some(handle) = self.flusher.take() {
            let _ = handle.join();
        }
    }
}

impl Default for Logs {
    fn default() -> Self {
        // Every engine owns its own flusher; `new` is the only constructor.
        Self::new()
    }
}

impl Drop for Logs {
    fn drop(&mut self) {
        self.stop();
    }
}

fn flush_loop(
    aggregator: Arc<LogAggregator>,
    sink: Arc<RwLock<Option<Arc<dyn EventSink>>>>,
    receiver: Receiver<Wake>,
    stopped: Arc<AtomicBool>,
) {
    loop {
        let pending = aggregator.pending();
        if pending == 0 {
            match receiver.recv() {
                Ok(Wake::Rows) => continue,
                Ok(Wake::Stop) | Err(_) => break,
            }
        }
        if pending >= BATCH_SIZE {
            emit(&aggregator, &sink, BATCH_SIZE);
            continue;
        }
        match receiver.recv_timeout(FLUSH_INTERVAL) {
            Ok(Wake::Rows) => {}
            Ok(Wake::Stop) => break,
            Err(RecvTimeoutError::Timeout) => {
                emit(&aggregator, &sink, usize::MAX);
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }
    // `drainAll` on the way out: a stopped engine must not swallow the last rows.
    if stopped.load(Ordering::Acquire) {
        while emit(&aggregator, &sink, BATCH_SIZE) == BATCH_SIZE {}
    }
}

/// Drains at most `max` rows and hands them to the sink; returns how many rows went out.
fn emit(
    aggregator: &LogAggregator,
    sink: &Arc<RwLock<Option<Arc<dyn EventSink>>>>,
    max: usize,
) -> usize {
    let (rows, _) = aggregator.drain(max);
    if rows.is_empty() {
        return 0;
    }
    let target = sink.read().ok().and_then(|sink| sink.clone());
    if let Some(target) = target {
        target.batch(&batch_json(&rows));
    }
    rows.len()
}

/// `json.Marshal([]logItem)`: field names are read by `DnsLogWriter.writeBatch` and cannot change.
pub fn batch_json(rows: &[LogItem]) -> String {
    let document: Vec<serde_json::Value> = rows
        .iter()
        .map(|row| {
            serde_json::json!({
                "d": row.domain,
                "b": row.blocked,
                "t": row.query_type,
                "r": row.response_time_ms,
                "a": row.app_name,
                "i": row.resolved_ips,
                "k": row.blocked_by,
                "e": row.error_message,
                "c": row.cached,
                "ts": row.timestamp_ms,
                "ttl": row.ttl,
            })
        })
        .collect();
    serde_json::Value::Array(document).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[derive(Default)]
    struct Recorder {
        batches: Mutex<Vec<String>>,
        races: Mutex<Vec<RaceEvent>>,
    }

    impl EventSink for Recorder {
        fn batch(&self, json: &str) {
            self.batches.lock().unwrap().push(json.to_string());
        }

        fn race(&self, event: &RaceEvent) {
            self.races.lock().unwrap().push(event.clone());
        }

        fn bootstrap(&self, _event: &BootstrapEvent) {}
    }

    fn item(domain: &str) -> LogItem {
        LogItem {
            domain: domain.to_string(),
            blocked: false,
            query_type: 1,
            response_time_ms: 3,
            app_name: "RootProxy".to_string(),
            resolved_ips: "1.2.3.4".to_string(),
            blocked_by: String::new(),
            error_message: String::new(),
            cached: false,
            timestamp_ms: 1_700_000_000_000,
            ttl: 60,
        }
    }

    #[test]
    fn batch_json_keeps_the_kotlin_field_names() {
        let json = batch_json(&[item("example.test")]);
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("json");
        let row = &parsed[0];
        for key in ["d", "b", "t", "r", "a", "i", "k", "e", "c", "ts", "ttl"] {
            assert!(row.get(key).is_some(), "missing {key} in {json}");
        }
        assert_eq!(
            row["ttl"],
            serde_json::json!(60),
            "a zero TTL is still present"
        );
    }

    #[test]
    fn flushes_complete_batches_and_the_tail() {
        let logs = Logs::new();
        let recorder = Arc::new(Recorder::default());
        logs.set_sink(Some(recorder.clone()));

        for index in 0..BATCH_SIZE {
            logs.push(item(&format!("batch{index}.test")));
        }
        // The flusher runs on its own thread; give it a moment to drain the full batch.
        let deadline = std::time::Instant::now() + Duration::from_secs(2);
        while recorder.batches.lock().unwrap().is_empty() && std::time::Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(recorder.batches.lock().unwrap().len(), 1);

        logs.push(item("tail.test"));
        let deadline = std::time::Instant::now() + Duration::from_secs(2);
        while recorder.batches.lock().unwrap().len() < 2 && std::time::Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        assert_eq!(
            recorder.batches.lock().unwrap().len(),
            2,
            "the partial tail is flushed by the timer"
        );
    }

    #[test]
    fn rows_without_a_sink_are_not_queued() {
        let logs = Logs::new();
        logs.push(item("dropped.test"));
        assert_eq!(logs.pending(), 0);
        assert!(!logs.has_sink());
    }
}

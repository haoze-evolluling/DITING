//! The batch DNS log, the race log and the bootstrap log.
//!
//! `log_aggregator.go` kept three things around the Rust buffer: the flush goroutine and its
//! lazily-armed 100 ms timer, the `encoding/json` of a drained batch, and the Kotlin callback. That
//! is what [`Logs`] is: the buffer is [`diting_telemetry_core::LogAggregator`] (2048 slots, the 3/4
//! high-water shed, the two drop counters), and everything around it is here.
//!
//! A drained batch crosses the boundary as one packed `byte[]` in the log kernel's own input layout
//! ([`batch_payload`]), not as JSON. Kotlin hands the same buffer to `LogNative.dnsBatch`, so the
//! rows are encoded once by the producer and are never parsed or rebuilt on the JVM side.
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
    /// One dial result; it reaches Kotlin in the engine's batched
    /// `BootstrapLogCallback.onBootstrapEvents`.
    fn bootstrap(&self, event: &BootstrapEvent);
}

/// What the engine reports to the app.
///
/// Both implementations are cheap and non-blocking on the caller's thread: the JNI one posts to the
/// Kotlin object from the flusher thread, a test one just records.
pub trait EventSink: Send + Sync {
    /// `BatchLogCallback.onDNSQueryBatch`: one packed batch, see [`batch_payload`].
    fn batch(&self, payload: &[u8]);
    /// `RaceLogCallback.onRaceEvents`: the sink takes ownership so the buffered batch does not
    /// clone five strings per event.
    fn race(&self, event: RaceEvent);
    /// `BootstrapLogCallback.onBootstrapEvents`, same ownership rule.
    fn bootstrap(&self, event: BootstrapEvent);
    /// Whether DNS rows should be buffered at all: a sink that only carries race/bootstrap events
    /// must not grow the 2048-row buffer for rows it will never deliver.
    fn wants_batch(&self) -> bool {
        true
    }
    /// Delivers anything the sink itself has buffered. Called before the writer queues close, so a
    /// batch that was still waiting for its timer does not land after them.
    fn flush(&self) {}
}

/// The engine's log plumbing: the buffer, the flusher thread and the current sink.
pub struct Logs {
    aggregator: Arc<LogAggregator>,
    sink: Arc<RwLock<Option<Arc<dyn EventSink>>>>,
    /// `sink.wants_batch()`, cached: [`Logs::push`] runs on every DNS query and must not take the
    /// sink lock or a dynamic call just to learn that no batch callback is installed.
    wanted: Arc<AtomicBool>,
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
        let wanted = Arc::new(AtomicBool::new(false));
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
            wanted,
            wake,
            stopped,
            flusher: Some(flusher),
        }
    }

    /// Posts one row, mirroring `notifyLog`'s "batch callback first, then the single callback".
    pub fn push(&self, item: LogItem) {
        if !self.wanted.load(Ordering::Acquire) {
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
        // Cached before the sink becomes visible, so a racing `push` either sees the old answer or
        // the new one, never a published sink with the cache still false.
        let wanted = sink.as_ref().is_some_and(|sink| sink.wants_batch());
        self.wanted.store(wanted, Ordering::Release);
        if let Ok(mut current) = self.sink.write() {
            *current = sink;
        }
    }

    /// Drains every buffered DNS row to the current sink on the caller's thread, then asks the sink
    /// to deliver its own buffers. Called on teardown, before the writer queues close: the flusher
    /// thread's partial batch would otherwise still be waiting for its timer.
    pub fn flush(&self) {
        let sink = self.sink.read().ok().and_then(|sink| sink.clone());
        let Some(sink) = sink else {
            return;
        };
        loop {
            let (rows, _) = self.aggregator.drain(BATCH_SIZE);
            if rows.is_empty() {
                break;
            }
            sink.batch(&batch_payload(&rows));
        }
        sink.flush();
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
            sink.race(event);
        }
    }

    pub fn bootstrap(&self, event: BootstrapEvent) {
        let sink = self.sink.read().ok().and_then(|sink| sink.clone());
        if let Some(sink) = sink {
            sink.bootstrap(event);
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
        target.batch(&batch_payload(&rows));
    }
    rows.len()
}

// ---------------------------------------------------------------------------------------------
// Packed batches: the log kernel's input layout, encoded once on the producer side
// ---------------------------------------------------------------------------------------------

fn push_u8(out: &mut Vec<u8>, value: u8) {
    out.push(value);
}

fn push_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_be_bytes());
}

fn push_i32(out: &mut Vec<u8>, value: i32) {
    out.extend_from_slice(&value.to_be_bytes());
}

fn push_i64(out: &mut Vec<u8>, value: i64) {
    out.extend_from_slice(&value.to_be_bytes());
}

/// `u32 length | UTF-8`, the same string framing every log payload uses.
fn push_str(out: &mut Vec<u8>, value: &str) {
    push_u32(out, value.len() as u32);
    out.extend_from_slice(value.as_bytes());
}

/// One `dns_log` batch: `u32 count` then, per row,
/// `i64 ts | string domain | i32 type | u8 blocked | string blocked_by | string error |
/// u8 cached | string app | string resolved | i64 elapsed`.
///
/// This is exactly the payload `diting_log_core::api::dns_batch` decodes, so `DnsLogWriter` can
/// forward it without touching its contents. The `ttl` field of [`LogItem`] is not part of the log
/// row and stays out of the batch.
pub fn batch_payload(rows: &[LogItem]) -> Vec<u8> {
    let strings: usize = rows
        .iter()
        .map(|row| {
            row.domain.len()
                + row.blocked_by.len()
                + row.error_message.len()
                + row.app_name.len()
                + row.resolved_ips.len()
        })
        .sum();
    let mut out = Vec::with_capacity(4 + rows.len() * 32 + strings + rows.len() * 5 * 4);
    push_u32(&mut out, rows.len() as u32);
    for row in rows {
        push_i64(&mut out, row.timestamp_ms);
        push_str(&mut out, &row.domain);
        push_i32(&mut out, row.query_type);
        push_u8(&mut out, u8::from(row.blocked));
        push_str(&mut out, &row.blocked_by);
        push_str(&mut out, &row.error_message);
        push_u8(&mut out, u8::from(row.cached));
        push_str(&mut out, &row.app_name);
        push_str(&mut out, &row.resolved_ips);
        push_i64(&mut out, row.response_time_ms);
    }
    out
}

/// One `dns_race_log` batch, in the layout `diting_log_core::api::race_batch` decodes.
pub fn race_batch_payload(events: &[RaceEvent]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + events.len() * 96);
    push_u32(&mut out, events.len() as u32);
    for event in events {
        push_str(&mut out, &event.query_name);
        push_i32(&mut out, i32::from(event.query_type));
        push_str(&mut out, &event.strategy);
        push_i32(&mut out, event.provider_count as i32);
        push_u8(&mut out, u8::from(event.success));
        push_i64(&mut out, event.elapsed_ms);
        push_str(&mut out, &event.selected_provider_id);
        push_i64(&mut out, event.selected_elapsed_ms);
        push_str(&mut out, &event.winner_provider_id);
        push_i64(&mut out, event.winner_elapsed_ms);
        push_u8(&mut out, u8::from(event.fallback_used));
        push_u8(&mut out, u8::from(event.fallback_success));
        push_str(&mut out, &event.error_message);
    }
    out
}

/// One `bootstrap_log` batch, in the layout `diting_log_core::api::bootstrap_batch` decodes.
pub fn bootstrap_batch_payload(events: &[BootstrapEvent]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + events.len() * 64);
    push_u32(&mut out, events.len() as u32);
    for event in events {
        push_str(&mut out, &event.ip_id);
        push_str(&mut out, &event.ip_name);
        push_str(&mut out, &event.ip);
        push_str(&mut out, &event.host);
        push_u8(&mut out, u8::from(event.success));
        push_i64(&mut out, event.elapsed_ms);
        push_u8(&mut out, u8::from(event.fallback_used));
        push_str(&mut out, &event.error_message);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[derive(Default)]
    struct Recorder {
        batches: Mutex<Vec<Vec<u8>>>,
        races: Mutex<Vec<RaceEvent>>,
    }

    impl EventSink for Recorder {
        fn batch(&self, payload: &[u8]) {
            self.batches.lock().unwrap().push(payload.to_vec());
        }

        fn race(&self, event: RaceEvent) {
            self.races.lock().unwrap().push(event);
        }

        fn bootstrap(&self, _event: BootstrapEvent) {}
    }

    /// Splits the packed layout the JVM receives back into its fields.
    fn decode_batch(payload: &[u8]) -> Vec<Vec<u8>> {
        let mut offset = 4usize;
        let count = u32::from_be_bytes(payload[0..4].try_into().unwrap()) as usize;
        let mut rows = Vec::with_capacity(count);
        for _ in 0..count {
            let start = offset;
            offset += 8; // timestamp
            offset += 4; // domain length
            let domain_len =
                u32::from_be_bytes(payload[start + 8..start + 12].try_into().unwrap()) as usize;
            offset += domain_len;
            offset += 4; // query type
            offset += 1; // blocked
            for _ in 0..2 {
                // blocked_by and error_message
                let length =
                    u32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap()) as usize;
                offset += 4 + length;
            }
            offset += 1; // cached
            for _ in 0..2 {
                // app_name and resolved_ips
                let length =
                    u32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap()) as usize;
                offset += 4 + length;
            }
            offset += 8; // elapsed
            rows.push(payload[start..offset].to_vec());
        }
        assert_eq!(offset, payload.len(), "the batch has trailing bytes");
        rows
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
    fn the_batch_payload_is_the_log_kernel_input_layout() {
        let payload = batch_payload(&[item("example.test")]);
        assert_eq!(
            u32::from_be_bytes(payload[0..4].try_into().unwrap()),
            1,
            "the count leads the payload"
        );

        let mut offset = 4;
        let timestamp = i64::from_be_bytes(payload[offset..offset + 8].try_into().unwrap());
        offset += 8;
        let length = u32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap()) as usize;
        offset += 4;
        let domain = std::str::from_utf8(&payload[offset..offset + length]).unwrap();
        offset += length;
        let query_type = i32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap());
        offset += 4;
        let blocked = payload[offset];

        assert_eq!(timestamp, 1_700_000_000_000);
        assert_eq!(domain, "example.test");
        assert_eq!(query_type, 1);
        assert_eq!(blocked, 0);

        let rows = decode_batch(&payload);
        assert_eq!(rows.len(), 1, "one row round trips");
    }

    #[test]
    fn the_race_batch_payload_carries_every_field_in_order() {
        let event = RaceEvent {
            query_name: "Example.test".to_string(),
            query_type: 28,
            strategy: "race".to_string(),
            provider_count: 3,
            success: true,
            elapsed_ms: 40,
            selected_provider_id: "p1".to_string(),
            selected_elapsed_ms: 12,
            winner_provider_id: String::new(),
            winner_elapsed_ms: 0,
            fallback_used: false,
            fallback_success: false,
            error_message: String::new(),
        };
        let payload = race_batch_payload(&[event]);
        // `u32 count | string query_name | i32 type | string strategy | ...`
        assert_eq!(u32::from_be_bytes(payload[0..4].try_into().unwrap()), 1);
        let length = u32::from_be_bytes(payload[4..8].try_into().unwrap()) as usize;
        assert_eq!(&payload[8..8 + length], b"Example.test");
    }

    #[test]
    fn the_bootstrap_batch_payload_starts_with_the_ip_id() {
        let event = BootstrapEvent {
            ip_id: "cloudflare".to_string(),
            ip_name: "Cloudflare".to_string(),
            ip: "1.1.1.1".to_string(),
            host: "cloudflare-dns.com".to_string(),
            success: true,
            elapsed_ms: 12,
            fallback_used: false,
            error_message: String::new(),
        };
        let payload = bootstrap_batch_payload(&[event]);
        assert_eq!(u32::from_be_bytes(payload[0..4].try_into().unwrap()), 1);
        let length = u32::from_be_bytes(payload[4..8].try_into().unwrap()) as usize;
        assert_eq!(&payload[8..8 + length], b"cloudflare");
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

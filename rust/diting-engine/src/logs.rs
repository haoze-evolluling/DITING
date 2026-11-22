use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, RwLock};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use diting_telemetry_core::{LogAggregator, LogItem, PushOutcome};

pub const BATCH_SIZE: usize = 50;
pub const FLUSH_INTERVAL: Duration = Duration::from_millis(100);

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

pub trait BootstrapSink: Send + Sync {
    fn bootstrap(&self, event: &BootstrapEvent);
}

pub trait EventSink: Send + Sync {
    fn batch(&self, payload: &[u8]);
    fn race(&self, event: RaceEvent);
    fn bootstrap(&self, event: BootstrapEvent);
    fn wants_batch(&self) -> bool {
        true
    }
    fn flush(&self) {}
}

pub struct Logs {
    aggregator: Arc<LogAggregator>,
    sink: Arc<RwLock<Option<Arc<dyn EventSink>>>>,
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
    pub fn new() -> Self {
        let aggregator = Arc::new(LogAggregator::new());
        let (wake, receiver) = mpsc::channel();
        let stopped = Arc::new(AtomicBool::new(false));
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

    /// 是否有 sink 真正想要这批日志。无锁读取，供热路径在构造日志行之前短路。
    pub fn wants(&self) -> bool {
        self.wanted.load(Ordering::Acquire)
    }

    pub fn set_sink(&self, sink: Option<Arc<dyn EventSink>>) {
        let wanted = sink.as_ref().is_some_and(|sink| sink.wants_batch());
        self.wanted.store(wanted, Ordering::Release);
        if let Ok(mut current) = self.sink.write() {
            *current = sink;
        }
    }

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

#[derive(Debug, Default)]
pub struct DiscardBootstrapSink;

impl BootstrapSink for DiscardBootstrapSink {
    fn bootstrap(&self, _event: &BootstrapEvent) {}
}

impl Logs {
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
    if stopped.load(Ordering::Acquire) {
        while emit(&aggregator, &sink, BATCH_SIZE) == BATCH_SIZE {}
    }
}

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

fn push_str(out: &mut Vec<u8>, value: &str) {
    push_u32(out, value.len() as u32);
    out.extend_from_slice(value.as_bytes());
}

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

    fn decode_batch(payload: &[u8]) -> Vec<Vec<u8>> {
        let mut offset = 4usize;
        let count = u32::from_be_bytes(payload[0..4].try_into().unwrap()) as usize;
        let mut rows = Vec::with_capacity(count);
        for _ in 0..count {
            let start = offset;
            offset += 8;
            offset += 4;
            let domain_len =
                u32::from_be_bytes(payload[start + 8..start + 12].try_into().unwrap()) as usize;
            offset += domain_len;
            offset += 4;
            offset += 1;
            for _ in 0..2 {
                let length =
                    u32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap()) as usize;
                offset += 4 + length;
            }
            offset += 1;
            for _ in 0..2 {
                let length =
                    u32::from_be_bytes(payload[offset..offset + 4].try_into().unwrap()) as usize;
                offset += 4 + length;
            }
            offset += 8;
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

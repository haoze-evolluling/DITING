//! Asynchronous daily JSON-Lines writer.
//!
//! Port of `desktop/service/internal/querylog/writer.go`. The DNS hot path only performs a
//! non-blocking enqueue; one background thread owns the file handle, rotates by local date,
//! flushes every second (or every 256 lines) and performs retention cleanup on start.

use std::fs::{self, File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use chrono::{DateTime, Local, LocalResult, NaiveDate, TimeZone};
use tokio::sync::mpsc;

use super::types::Record;

/// Bounded record queue; full means "drop", never block the resolver.
pub(crate) const QUEUE_SIZE: usize = 4096;
/// Flush once this many lines are buffered.
pub(crate) const FLUSH_LINES: usize = 256;
/// Periodic flush / rotation interval.
pub(crate) const FLUSH_INTERVAL: Duration = Duration::from_secs(1);
/// Log file prefix.
pub(crate) const FILE_PREFIX: &str = "querylog-";
/// Log file suffix.
pub(crate) const FILE_SUFFIX: &str = ".jsonl";
/// Daily rollover date layout.
pub(crate) const DAY_LAYOUT: &str = "%Y%m%d";

const DAY_MS: i64 = 24 * 60 * 60 * 1000;

type Clock = Arc<dyn Fn() -> DateTime<Local> + Send + Sync>;

#[allow(dead_code)]
enum Control {
    Flush(std::sync::mpsc::Sender<()>),
    Clear(std::sync::mpsc::Sender<io::Result<()>>),
    Shutdown(std::sync::mpsc::Sender<()>),
}

/// Whether `name` is a query-log file.
pub(crate) fn is_log_file_name(name: &str) -> bool {
    name.starts_with(FILE_PREFIX) && name.ends_with(FILE_SUFFIX)
}

/// Log files sorted ascending by date (file name).
pub(crate) fn list_log_files(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter(|name| is_log_file_name(name))
        .collect();
    names.sort();
    names
        .into_iter()
        .map(|name| dir.join(name))
        .collect::<Vec<_>>()
}

/// Local-midnight timestamp encoded in a log file's name, or `None` when it does not parse.
pub(crate) fn file_date_ms(path: &Path) -> Option<i64> {
    let name = path.file_name()?.to_str()?;
    parse_day_ms(name)
}

fn parse_day_ms(name: &str) -> Option<i64> {
    let day = name.strip_prefix(FILE_PREFIX)?.strip_suffix(FILE_SUFFIX)?;
    if day.len() != 8 || !day.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let year: i32 = day[0..4].parse().ok()?;
    let month: u32 = day[4..6].parse().ok()?;
    let day_of_month: u32 = day[6..8].parse().ok()?;
    let date = NaiveDate::from_ymd_opt(year, month, day_of_month)?;
    let midnight = date.and_hms_opt(0, 0, 0)?;
    match Local.from_local_datetime(&midnight) {
        LocalResult::Single(dt) => Some(dt.timestamp_millis()),
        LocalResult::Ambiguous(dt, _) => Some(dt.timestamp_millis()),
        LocalResult::None => None,
    }
}

struct WriterState {
    dir: PathBuf,
    retention_days: i32,
    clock: Clock,
    file: Option<BufWriter<File>>,
    cur_day: String,
    pending: usize,
}

impl WriterState {
    fn new(dir: PathBuf, retention_days: i32, clock: Clock) -> Self {
        Self {
            dir,
            retention_days,
            clock,
            file: None,
            cur_day: String::new(),
            pending: 0,
        }
    }

    fn day(&self) -> String {
        (self.clock)().format(DAY_LAYOUT).to_string()
    }

    fn write_record(&mut self, record: &Record) {
        let Ok(data) = serde_json::to_vec(record) else {
            return;
        };
        if self.ensure_file().is_err() {
            return;
        }
        let Some(file) = self.file.as_mut() else {
            return;
        };
        if file.write_all(&data).is_err() || file.write_all(b"\n").is_err() {
            return;
        }
        self.pending += 1;
        if self.pending >= FLUSH_LINES {
            self.flush();
        }
    }

    fn ensure_file(&mut self) -> io::Result<()> {
        let day = self.day();
        if self.file.is_some() && self.cur_day == day {
            return Ok(());
        }
        self.flush();
        self.close_file();

        let path = self.dir.join(format!("{FILE_PREFIX}{day}{FILE_SUFFIX}"));
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        self.file = Some(BufWriter::with_capacity(64 * 1024, file));
        self.cur_day = day;
        Ok(())
    }

    fn rotate_if_needed(&mut self) {
        if self.file.is_none() {
            return;
        }
        if self.day() != self.cur_day {
            self.flush();
            self.close_file();
        }
    }

    fn flush(&mut self) {
        if let Some(file) = self.file.as_mut() {
            let _ = file.flush();
        }
        self.pending = 0;
    }

    fn close_file(&mut self) {
        if let Some(mut file) = self.file.take() {
            let _ = file.flush();
        }
        self.pending = 0;
    }

    fn cleanup(&self) {
        if self.retention_days <= 0 {
            return;
        }
        let cutoff_ms = (self.clock)().timestamp_millis() - i64::from(self.retention_days) * DAY_MS;
        for path in list_log_files(&self.dir) {
            if let Some(file_ms) = file_date_ms(&path) {
                if file_ms < cutoff_ms {
                    let _ = fs::remove_file(&path);
                }
            }
        }
    }

    fn remove_files(&mut self) -> io::Result<()> {
        self.close_file();
        let mut errors = Vec::new();
        for path in list_log_files(&self.dir) {
            if let Err(error) = fs::remove_file(&path) {
                let name = path
                    .file_name()
                    .map(|name| name.to_string_lossy().into_owned())
                    .unwrap_or_default();
                errors.push(format!("{name}: {error}"));
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(io::Error::other(format!(
                "删除查询日志文件失败: {}",
                errors.join("; ")
            )))
        }
    }
}

fn run_writer(
    mut records: mpsc::Receiver<Record>,
    mut controls: mpsc::UnboundedReceiver<Control>,
    mut state: WriterState,
) {
    state.cleanup();
    let mut last_flush = Instant::now();
    loop {
        let mut idle = true;
        while let Ok(record) = records.try_recv() {
            state.write_record(&record);
            idle = false;
        }

        match controls.try_recv() {
            Ok(Control::Flush(ack)) => {
                state.flush();
                let _ = ack.send(());
                idle = false;
            }
            Ok(Control::Clear(ack)) => {
                while let Ok(record) = records.try_recv() {
                    state.write_record(&record);
                }
                let result = state.remove_files();
                let _ = ack.send(result);
                last_flush = Instant::now();
                idle = false;
            }
            Ok(Control::Shutdown(ack)) => {
                while let Ok(record) = records.try_recv() {
                    state.write_record(&record);
                }
                state.flush();
                state.close_file();
                let _ = ack.send(());
                return;
            }
            Err(tokio::sync::mpsc::error::TryRecvError::Empty) => {}
            Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                while let Ok(record) = records.try_recv() {
                    state.write_record(&record);
                }
                state.flush();
                state.close_file();
                return;
            }
        }

        if last_flush.elapsed() >= FLUSH_INTERVAL {
            state.rotate_if_needed();
            state.flush();
            last_flush = Instant::now();
        }
        if idle {
            std::thread::sleep(Duration::from_millis(10));
        }
    }
}

/// Handle to the asynchronous writer thread.
pub(crate) struct Writer {
    records: mpsc::Sender<Record>,
    controls: mpsc::UnboundedSender<Control>,
    handle: Mutex<Option<JoinHandle<()>>>,
    dir: PathBuf,
    retention_days: i32,
}

impl Writer {
    /// Create the writer and verify `dir` is writable (probe file), or return an error so the
    /// facade can degrade to memory-only mode.
    pub(crate) fn new(dir: impl Into<PathBuf>, retention_days: i32) -> io::Result<Self> {
        Self::new_with_clock(dir, retention_days, Arc::new(Local::now))
    }

    fn new_with_clock(
        dir: impl Into<PathBuf>,
        retention_days: i32,
        clock: Clock,
    ) -> io::Result<Self> {
        let dir = dir.into();
        if dir.as_os_str().is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "查询日志目录为空",
            ));
        }
        fs::create_dir_all(&dir)?;
        let probe = dir.join(".probe");
        fs::write(&probe, [])?;
        let _ = fs::remove_file(&probe);

        let (records, records_rx) = mpsc::channel(QUEUE_SIZE);
        let (controls, controls_rx) = mpsc::unbounded_channel();
        let state = WriterState::new(dir.clone(), retention_days, clock);
        let handle = std::thread::Builder::new()
            .name("diting-querylog-writer".into())
            .spawn(move || run_writer(records_rx, controls_rx, state))?;

        Ok(Self {
            records,
            controls,
            handle: Mutex::new(Some(handle)),
            dir,
            retention_days,
        })
    }

    /// Non-blocking enqueue; returns `false` when the queue is full or the writer is closed.
    pub(crate) fn enqueue(&self, record: Record) -> bool {
        self.records.try_send(record).is_ok()
    }

    /// Pending persistence directory.
    pub(crate) fn dir(&self) -> &Path {
        &self.dir
    }

    /// Pending persistence retention.
    pub(crate) fn retention_days(&self) -> i32 {
        self.retention_days
    }

    /// Wait until buffered records have been flushed (used by tests / graceful paths).
    #[allow(dead_code)]
    pub(crate) fn flush_blocking(&self) -> io::Result<()> {
        let (ack, wait) = std::sync::mpsc::channel();
        if self.controls.send(Control::Flush(ack)).is_err() {
            return Ok(());
        }
        wait.recv_timeout(Duration::from_secs(10))
            .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "等待查询日志刷新超时"))
    }

    /// Close the current handle and delete every log file.
    pub(crate) fn clear(&self) -> io::Result<()> {
        let (ack, wait) = std::sync::mpsc::channel();
        if self.controls.send(Control::Clear(ack)).is_err() {
            return Ok(());
        }
        match wait.recv_timeout(Duration::from_secs(10)) {
            Ok(result) => result,
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "等待查询日志清理超时",
            )),
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => Ok(()),
        }
    }

    /// Drain queued records, flush and stop the background thread.
    pub(crate) fn close(&self) -> io::Result<()> {
        let handle = self.handle.lock().unwrap_or_else(|e| e.into_inner()).take();
        let Some(handle) = handle else {
            return Ok(());
        };
        let (ack, wait) = std::sync::mpsc::channel();
        if self.controls.send(Control::Shutdown(ack)).is_ok() {
            let _ = wait.recv_timeout(Duration::from_secs(10));
        }
        handle
            .join()
            .map_err(|_| io::Error::other("查询日志写入线程异常退出"))
    }
}

impl Drop for Writer {
    fn drop(&mut self) {
        let _ = self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::querylog::unique_temp_dir;
    use std::sync::atomic::{AtomicI64, Ordering};

    fn fixed_clock(initial_ms: i64) -> (Arc<AtomicI64>, Clock) {
        let millis = Arc::new(AtomicI64::new(initial_ms));
        let setter = Arc::clone(&millis);
        let clock: Clock = Arc::new(move || {
            Local
                .timestamp_millis_opt(setter.load(Ordering::SeqCst))
                .single()
                .unwrap_or_else(Local::now)
        });
        (millis, clock)
    }

    fn record(timestamp: i64, domain: &str, status: &str) -> Record {
        Record {
            timestamp,
            domain: domain.into(),
            status: status.into(),
            ..Record::default()
        }
    }

    #[test]
    fn append_close_and_read_back() {
        let dir = unique_temp_dir("writer-append");
        let (_, clock) = fixed_clock(1_792_000_000_000);
        let writer = Writer::new_with_clock(&dir, 7, clock).expect("writer");
        assert!(writer.enqueue(record(1, "a.com", "allowed")));
        assert!(writer.enqueue(record(2, "b.com", "blocked")));
        writer.close().expect("close");

        let files = list_log_files(&dir);
        assert_eq!(files.len(), 1);
        let content = fs::read_to_string(&files[0]).expect("read");
        let lines: Vec<&str> = content.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("a.com"));
        assert!(lines[1].contains("b.com"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rotates_on_local_day_change() {
        let dir = unique_temp_dir("writer-rotate");
        let day1 = Local
            .with_ymd_and_hms(2026, 10, 13, 23, 59, 0)
            .single()
            .expect("day1");
        let day2 = Local
            .with_ymd_and_hms(2026, 10, 14, 0, 1, 0)
            .single()
            .expect("day2");
        let (millis, clock) = fixed_clock(day1.timestamp_millis());
        let writer = Writer::new_with_clock(&dir, 7, clock).expect("writer");

        writer.enqueue(record(day1.timestamp_millis(), "day1.com", "allowed"));
        writer.flush_blocking().expect("flush day1");
        millis.store(day2.timestamp_millis(), Ordering::SeqCst);
        writer.enqueue(record(day2.timestamp_millis(), "day2.com", "allowed"));
        writer.flush_blocking().expect("flush day2");
        writer.close().expect("close");

        let files = list_log_files(&dir);
        assert_eq!(files.len(), 2, "expected one file per day: {files:?}");
        let first = fs::read_to_string(&files[0]).expect("read day1");
        let second = fs::read_to_string(&files[1]).expect("read day2");
        assert!(first.contains("day1.com"));
        assert!(second.contains("day2.com"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn retention_cleanup_removes_old_files() {
        let dir = unique_temp_dir("writer-retention");
        fs::create_dir_all(&dir).expect("mkdir");
        let now = Local
            .with_ymd_and_hms(2026, 10, 13, 12, 0, 0)
            .single()
            .expect("now");
        let old_path = dir.join(format!("{FILE_PREFIX}20260901{FILE_SUFFIX}"));
        let recent_path = dir.join(format!("{FILE_PREFIX}20261010{FILE_SUFFIX}"));
        fs::write(&old_path, b"{}\n").expect("seed old");
        fs::write(&recent_path, b"{}\n").expect("seed recent");

        let (_, clock) = fixed_clock(now.timestamp_millis());
        let writer = Writer::new_with_clock(&dir, 7, clock).expect("writer");

        let deadline = Instant::now() + Duration::from_secs(2);
        while old_path.exists() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        writer.close().expect("close");
        assert!(!old_path.exists(), "old file should be removed");
        assert!(recent_path.exists(), "recent file should be retained");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn unwritable_directory_is_rejected() {
        let dir = unique_temp_dir("writer-unwritable");
        let file = dir.join("afile");
        fs::write(&file, b"x").expect("write file");
        assert!(Writer::new(file.join("sub"), 7).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn file_date_parsing() {
        let path = Path::new("x").join(format!("{FILE_PREFIX}20261013{FILE_SUFFIX}"));
        let expected = Local
            .with_ymd_and_hms(2026, 10, 13, 0, 0, 0)
            .single()
            .expect("midnight")
            .timestamp_millis();
        assert_eq!(file_date_ms(&path), Some(expected));
        assert_eq!(file_date_ms(Path::new("garbage.txt")), None);
    }
}

//! Rust core for the Android app's log and statistics backend.
//!
//! The Kotlin `log` package keeps every SQLite statement, every `Log.w`, the `org.json` decode of
//! the engine callbacks and the Android APIs (`ConnectivityManager`, `PackageManager`, `logcat`);
//! what moves here is the judgement on top of it:
//!
//! * [`row`] - what one engine callback becomes in `dns_log` / `http_request_log` /
//!   `dns_race_log` / `bootstrap_log`: the result classification, the log-mode filter, the
//!   `message` assembly, the subscription id and the blank defaults.
//! * [`retention`] - the two retention windows (defaults, bounds, millisecond cutoffs), the pruned
//!   table list and the `DELETE` batch size.
//! * [`stats`] - the notification's request buckets (`RequestStats`) and the transfer rates
//!   (`TrafficRateMonitor`), sharing one handle because every reader takes both.
//! * [`traffic`] - the per-UID traffic buffer behind `app_traffic_daily`: bucketing by date and
//!   package, the flush threshold, the overflow drop and the requeue of a failed write.
//! * [`health`] - `DbWriteHealth`'s drop counters and its one-line-per-minute warning window.
//! * [`attr`] - the two attribution LRUs behind `UidPackageCache` (TTLs, capacities, promotion).
//! * [`crash`] - `CrashTail.select`: keep only the crash-buffer blocks that name this package.
//! * [`store`] - `RuntimeLogStore`: which capture files exist and survive a trim, and the export
//!   document (header, per-file sections, crash tail).
//! * [`capture`] - `RuntimeLogService`: the `logcat` attempts, the watchdog cadence and the
//!   per-file byte budget that decides a rotation.
//! * [`mirror`] - `DnsCacheMirror`: how much of the engine's cache is projected, how often, and the
//!   `dns_cache` row shape with its two constant columns.
//! * [`queue`] - the queues behind `LogTableWriter` and `HttpRequestLogWriter`: the batch size, the
//!   pending cap with its oldest-first drop, the per-transaction chunk and the backoff window.
//! * [`api`] - the request/answer payload layouts, so every codec is testable without a JVM.
//! * [`jni`] - the entry points `com.haoze.diting.log.LogNative` declares, grouped by the
//!   Kotlin class they serve.
//!
//! There is no Kotlin implementation left to fall back to: a missing library or a payload from a
//! different layout version fails the write (or the read) instead of running a second classifier.

pub mod api;
pub mod attr;
pub mod capture;
pub mod crash;
pub mod health;
pub mod jni;
pub mod mirror;
pub mod payload;
pub mod queue;
pub mod retention;
pub mod row;
pub mod runtime_event;
pub mod stats;
pub mod store;
pub mod traffic;

pub use attr::{Attr, FlowKey, PackageLookup};
pub use crash::select as select_crash_blocks;
pub use health::{DropReason, Health, HealthSnapshot};
pub use queue::{Queue, Settings as QueueSettings};
pub use retention::{plan as retention_plan, Plan, StoredDays};
pub use row::{
    bootstrap_row, dns_result, dns_row, http_row, is_blank, lowercase, normalized_outcome,
    optional_text, race_row, subscription_id, BootstrapRow, DnsInput, DnsResult, DnsRow, HttpInput,
    HttpRow, LogMode, RaceInput, RaceRow,
};
pub use runtime_event::{
    at_least as level_at_least, format_event, Event, Gate as EventGate, Level,
};
pub use stats::{RequestSnapshot, Stats};
pub use traffic::{Delta, TickOutcome, TickRow, Traffic};

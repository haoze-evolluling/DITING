//! Rust core for the Android log read paths: the SQL plans, row classification and the aggregate
//! math behind the dashboard, request feed, race/bootstrap/subscription pages and statistics card.
//!
//! `RustLogQueryCore.instance` loads the library over `dart:ffi` and throws when the artifact is
//! missing or its ABI version differs, so a build that forgot `python rust/build_android.py` fails
//! on the first log page instead of quietly running a second copy of these rules.
//!
//! What stays in Dart: opening the databases, executing the statements (including the legacy
//! `no such table` / `no such column` tolerance), Riverpod orchestration, localised labels and the
//! `DateTime` calendar windows (their epoch values are passed in).
//!
//! Layout:
//! * [`sql`] — every read statement and its arguments.
//! * [`rows`] — raw SQLite rows to typed records, with the legacy defaults.
//! * [`classify`] — connection / block / rewrite markers, request buckets and `elapsed=` parsing.
//! * [`derive`] — daily statistics, merges, rates and the dashboard/statistics snapshots.
//! * [`ffi`] — the C ABI surface.

pub mod classify;
pub mod derive;
pub mod ffi;
mod overview;
pub mod payload;
pub mod rows;
pub mod sql;
mod util;

pub use ffi::ABI_VERSION;

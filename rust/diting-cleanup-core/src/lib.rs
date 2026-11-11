//! The data-cleanup catalog: every table, source table, WHERE clause, preference key and the
//! `allData` action order lives here exactly once. Dart still opens databases, runs the statements,
//! deletes files and writes preferences; this crate only answers what to do.
//!
//! Retention days and log mode stay in `shared` settings: the native writer reads those keys from
//! each data set, so duplicating their defaults here would create a second source of truth.

mod ffi;
mod plan;

pub use plan::plan;

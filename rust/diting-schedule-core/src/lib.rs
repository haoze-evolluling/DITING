//! The scheduling kernel shared by subscription auto-update, timed blocking and automation.
//!
//! Before this crate the subscription auto-update rules lived in `diting-subscription-core` and
//! could only express `interval` / `daily` / `every_other_day`. This crate extracts those rules
//! into a [`schedule`] `Cadence` and extends the same pure evaluator with `cron`, `window` and
//! `pause`, so every "run on a timetable" feature shares one implementation. `now` is injected and
//! the calendar is supplied by the caller (a local `day → slot` table for wall-clock cadences), so
//! the tests pin every boundary and DST stays exactly where the platform's timezone database is.
//!
//! Layout:
//! * [`payload`] — typed reads of the JSON payload; a shape that does not fit is `None`.
//! * [`civil`] — timezone-free civil calendar helpers (`days ↔ y/m/d`, weekday, minute-of-day).
//! * [`cron`] — the 5-field cron parser and its next/latest occurrence search.
//! * [`schedule`] — [`schedule::evaluate`] (one plan) and [`schedule::evaluate_rules`] (many rules).
//! * [`ffi`] — the C ABI surface for a `dart:ffi` caller.

pub mod civil;
pub mod cron;
pub mod ffi;
pub mod payload;
pub mod schedule;

pub use ffi::ABI_VERSION;
pub use schedule::{evaluate, evaluate_rules};

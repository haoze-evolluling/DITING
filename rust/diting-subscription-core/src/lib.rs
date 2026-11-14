//! Rust core for the Android subscription feature: URL/mirror rules, row and form normalisation,
//! the download policy and the auto-update schedule.
//!
//! `RustSubscriptionCore.instance` loads the library over `dart:ffi` and throws when the artifact is
//! missing or its ABI version differs, so a build that forgot `python rust/build_android.py` fails
//! on the first subscription page instead of quietly running a second copy of these rules.
//!
//! What stays in Dart: `Uri` parsing (the platform's normalisation feeds the components this crate
//! works on), the HTTP stack with its progress callback, `sqflite` statements, the localised
//! sentences and the Riverpod orchestration.
//!
//! Layout:
//! * [`url`] — placeholder set, Java `URLEncoder` spelling, name/line derivations, validation order.
//! * [`model`] — row defaults/spellings and the add/edit/mirror forms.
//! * [`fetch`] — attempt order, mirror fallback, status verdicts and validator headers.
//! * [`schedule`] — interval and wall-clock schedules, with the local day→slot table injected.
//! * [`ffi`] — the C ABI surface.

pub mod fetch;
pub mod ffi;
pub mod health;
pub mod model;
pub mod payload;
pub mod schedule;
pub mod url;

pub use ffi::ABI_VERSION;

//! Rust core for the Android backup file: one writer, one reader, no second copy of the semantics
//! in Dart.
//!
//! `RustBackupCore.instance` loads the library at runtime and throws when the artifact is missing or
//! its ABI version differs, so a build that forgot `python rust/build_android.py` fails on the first
//! export instead of quietly writing a file with the old code.
//!
//! The database itself stays in Dart: `sqflite` owns the connection and the `*_source` rows are an
//! insert-then-look-up detail. Everything the file means — which rows are user rows, what is deduped
//! against what, which counters the summary shows — lives here.
//!
//! Layout:
//! * [`groups`] — the fifteen groups, their keys and write order (`backup_models.dart`).
//! * [`export`] — document writer, envelope and group builders (`backup_exporter*.dart`).
//! * [`import`] — envelope validation, merges and the import plan (`backup_import*.dart`).
//! * [`value`] — JSON probes shared by both directions.
//! * [`ffi`] — the C ABI surface.

pub mod export;
pub mod ffi;
pub mod groups;
pub mod import;
pub mod value;

pub use export::{serialize, FORMAT, VERSION};
pub use ffi::ABI_VERSION;
pub use groups::{Group, ORDER};

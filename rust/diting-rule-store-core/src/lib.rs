//! Rust core for the Android rule tables: row→rule mapping, every identity predicate, and the
//! statement plan of an import or a source sweep.
//!
//! `RustRuleStoreCore.instance` loads the library at runtime and throws when the artifact is missing
//! or its ABI version differs, so a build that forgot `python rust/build_android.py` fails on the
//! first rule page instead of quietly running a second copy of the dedupe rules.
//!
//! SQLite stays in Dart: `sqflite` owns the connection, the transactions and the batches. What the
//! tables *mean* — which rows are one rule, what makes two rules the same, what a subscription
//! source is called, which statements an import queues — lives here.
//!
//! Layout:
//! * [`rows`] — joined / split rows to `MockRule` values (`rule_repository.dart`).
//! * [`probe`] — typed reads of the JSON payload.
//! * [`identity`] — unique-key predicates, insert rows and rewrite target types.
//! * [`import`] — import batches, source sweeps and orphan pages (`rule_importer.dart`).
//! * [`ffi`] — the C ABI surface.

pub mod ffi;
pub mod identity;
pub mod import;
pub mod probe;
pub mod rows;

pub use ffi::ABI_VERSION;
pub use identity::{rewrite_target_type, TargetType};
pub use rows::{rule_from_joined, rule_from_split};

//! Rust core for the Android rule importer: the parser the app and the rule pages use.
//!
//! This is the only implementation. `RustRuleCore.instance` loads the library at runtime and
//! throws when the artifact is missing or its ABI version differs, so a build that forgot
//! `python rust/build_android.py` fails the import instead of running a second parser.
//!
//! Layout:
//! * [`models`] — rule shapes, field-for-field with `rule_models.dart`.
//! * [`domain`] — domain normalization, literal IP checks (`rule_domain_utils.dart`).
//! * [`line`] — single-line adblock/URL/cosmetic parsing and dedupe keys.
//! * [`hosts`] — hosts and dnsmasq lines.
//! * [`document`] — per-line entry point plus dedupe/badfilter aggregation.
//! * [`ffi`] — C ABI and the binary payload Dart decodes.
//! * [`dtri`] — the mmap-able subscription-rule index writer (`MappedSubscriptionRuleIndex`).
//! * [`search`] — the lowercased rule-table search index behind the rules page filter.
//! * [`jni_bridge`] — the JNI entry point the Kotlin rule-index loader calls.

pub mod document;
pub mod domain;
pub mod dtri;
pub mod fast_hash;
pub mod ffi;
pub mod hosts;
pub mod jni_bridge;
pub mod keys;
pub mod line;
pub mod models;
pub mod modifiers;
pub mod search;
pub mod search_ffi;

pub use document::{parse_categorized_line, parse_document};
pub use dtri::compile as compile_rule_index;
pub use ffi::ABI_VERSION;
pub use models::{CategorizedLine, CategorizedRules, ParsedRule};
pub use search::RuleSearchIndex;
pub use search_ffi::SEARCH_ABI_VERSION;

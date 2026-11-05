//! Rust core for the Android rule importer: a line-for-line port of the Dart parser in
//! `android/app/lib/data/rules/`.
//!
//! The Dart implementation stays in place as the fallback: `RustRuleCore.instance` loads the
//! library at runtime and `parseCategorized` only takes the native path when it is available and
//! its ABI version matches, so a device without the artifact keeps the exact old behaviour.
//!
//! Layout:
//! * [`models`] — rule shapes, field-for-field with `rule_models.dart`.
//! * [`domain`] — domain normalization, literal IP checks (`rule_domain_utils.dart`).
//! * [`line`] — single-line adblock/URL/cosmetic parsing and dedupe keys.
//! * [`hosts`] — hosts and dnsmasq lines.
//! * [`document`] — per-line entry point plus dedupe/badfilter aggregation.
//! * [`ffi`] — C ABI and the binary payload Dart decodes.
//! * [`dtri`] — the mmap-able subscription-rule index writer (`MappedSubscriptionRuleIndex`).
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

pub use document::{parse_categorized_line, parse_document};
pub use dtri::compile as compile_rule_index;
pub use ffi::ABI_VERSION;
pub use models::{CategorizedLine, CategorizedRules, ParsedRule};

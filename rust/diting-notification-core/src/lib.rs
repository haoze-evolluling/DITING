//! Foreground-notification settings and detail line for the Android services.
//!
//! Kotlin keeps SharedPreferences, `NotificationCompat`, PendingIntents and the service-specific
//! titles. This crate owns the parts that used to be duplicated Kotlin rules: the ordered detail
//! items and their legacy speed-switch fallback, the custom/default/fallback running-text chain,
//! the localized label lookup, and the exact `请求 1,234  ·  ↑ 1.5 MB/s` formatting.
//!
//! The entry points are JNI-only (`com.haoze.diting.platform.NotificationNative`): the same
//! process already reads the counters from the log kernel, so the settings/formatting kernel has
//! no Dart surface.

mod compose;
mod jni_bridge;
mod settings;

pub use compose::{compose, format_number, format_rates, Stats};
pub use settings::{running_text, stats_items};

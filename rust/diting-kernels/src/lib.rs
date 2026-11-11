//! Umbrella cdylib: one `libditing_kernels.so` for the sixteen Flutter/Kotlin UI-side kernels.
//!
//! Each kernel crate is a normal Rust dependency here instead of its own `dlopen`'d `.so`. The
//! kernels keep exposing their `#[no_mangle] pub extern "C"` C ABI (Dart `lookupFunction`) and
//! `Java_...` JNI entry points. The `pub use` re-exports below force every dependency to be linked
//! into the final cdylib; verifier keeps all of their `#[no_mangle]` roots, so `--gc-sections` does
//! not drop any exported entry point (verified: the merged library exports exactly the 164 symbols
//! the sixteen standalone libraries exported, with none missing).
//!
//! `libditing_engine.so` stays a separate library on purpose: it is the data plane, has no
//! duplicated std/dependency bytes to share, and is kept isolated from the UI-side kernels.

#![allow(unused_imports)]

// Force the rlibs to be linked at all (edition 2021 needs an explicit reference).
pub use diting_agent_core;
pub use diting_app_update_core;
pub use diting_backup_core;
pub use diting_cleanup_core;
pub use diting_dns_config_core;
pub use diting_ip_quality_core;
pub use diting_log_core;
pub use diting_log_query_core;
pub use diting_notification_core;
pub use diting_outbound_proxy_core;
pub use diting_probe_core;
pub use diting_recognition_core;
pub use diting_rule_core;
pub use diting_rule_store_core;
pub use diting_subscription_core;
pub use diting_vpn_config_core;

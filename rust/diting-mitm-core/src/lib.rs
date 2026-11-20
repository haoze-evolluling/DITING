pub mod ffi;
pub mod filter;
pub mod pattern;
pub mod payload;
pub mod sensitive;

#[cfg(test)]
mod fixture;

pub use ffi::ABI_VERSION;
pub use filter::{
    BlacklistReport, FailureReport, Filter, DEFAULT_BLACKLIST_TTL_MS, FAILURE_WINDOW_MS,
};
pub use pattern::{match_host_pattern, path_match, BadPattern};
pub use sensitive::{is_ip_address, is_sensitive_host, SENSITIVE_KEYWORDS};

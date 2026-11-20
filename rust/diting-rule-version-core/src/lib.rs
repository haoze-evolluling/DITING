pub mod ffi;
pub mod version;

pub use ffi::ABI_VERSION;
pub use version::{diff, record, RuleDiff, VersionEntry, DEFAULT_MAX_VERSIONS};

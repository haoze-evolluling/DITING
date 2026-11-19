//! Standalone server-mode process.
//!
//! The crate owns only Android-specific process concerns: the server data root, the single-line
//! Unix-socket control protocol, privileged startup and the query-log observer. DNS, filtering,
//! caching and upstream scheduling stay in the shared desktop crates.

pub mod config;
pub mod control;
pub mod observer;
pub mod paths;
pub mod protocol;
pub mod runtime;

pub use config::ServerConfig;
pub use paths::ServerPaths;
pub use runtime::ServerRuntime;

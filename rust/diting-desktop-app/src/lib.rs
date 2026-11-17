//! Application runtime shared by the service binary and the management API.
//!
//! This crate owns the long-lived engines, the DNS listener lifecycle and the operations the HTTP
//! handlers call. It depends on the platform, core and data-plane crates; neither the binary nor the
//! IPC crate owns business state, which keeps the HTTP layer free of process concerns.

pub mod controller;
pub mod maintenance;
pub mod runtime;
pub mod settings;

pub use runtime::{dns_server_config, AppRuntime, PlatformHandles};

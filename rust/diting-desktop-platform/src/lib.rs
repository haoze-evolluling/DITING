//! Platform operations: paths, crash-heal state, DNS takeover, firewall, ports and service control.
//!
//! The shared value types live in `diting-desktop-api`; this crate performs the OS work. Windows
//! and Linux implementations are selected at compile time and expose the same capability traits so
//! the IPC and service layers never branch on the target OS.

pub mod error;
pub mod exec;
pub mod netutil;
pub mod paths;
pub mod ports;
pub mod privilege;
pub mod state;
pub mod traits;

#[cfg(unix)]
pub mod linux;

#[cfg(windows)]
pub mod windows;

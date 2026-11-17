//! Pure data shared by the desktop service crates.
//!
//! Nothing here performs I/O or owns runtime state: the config model, the IPC DTOs, the
//! `Controller` trait and the platform value types live here so `diting-desktop-core` and
//! `diting-desktop-ipc` can depend on them without a cycle.

pub mod config;
pub mod platform_types;
pub mod version;

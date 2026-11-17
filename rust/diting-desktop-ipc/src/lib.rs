//! The local management API.
//!
//! The route table and the JSON envelope are the Flutter desktop app's only data source, so this
//! crate reproduces the Go `internal/ipc` contract rather than inventing a new one.

pub mod assets;
pub mod auth;
pub mod cors;
pub mod handlers;
pub mod response;
pub mod router;
pub mod server;
pub mod static_files;
pub mod types;
pub mod ws;

pub use diting_desktop_app::AppRuntime;
pub use server::Server;

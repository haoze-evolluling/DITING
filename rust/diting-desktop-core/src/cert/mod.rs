//! Encrypted-DNS server certificate management.
//!
//! Mirrors the former Go service's `internal/core/cert_*.go`: the certificate material lives on disk and
//! only the parsed summary is ever exposed. Configuration never carries private-key material, so
//! the same [`CertConfig`](diting_desktop_api::config::security::CertConfig) can travel over IPC
//! or be written to `config.json` unchanged.

pub mod derive;
pub mod generate;
pub mod health;
pub mod manager;

mod material;

#[cfg(test)]
mod tests;

pub use derive::derive_cert_names;
pub use health::CertHealth;
pub use manager::{CertInfo, CertManager};

/// Fixed file name of a generated self-signed certificate.
pub const SELF_SIGNED_CERT_FILE: &str = "server.crt";
/// Fixed file name of a generated self-signed private key.
pub const SELF_SIGNED_KEY_FILE: &str = "server.key";
/// Imported PEM certificate file name (kept apart from the self-signed names).
pub const IMPORTED_CERT_FILE: &str = "imported.crt";
/// Imported PEM private-key file name.
pub const IMPORTED_KEY_FILE: &str = "imported.key";
/// Renewal window used by [`CertHealth::needs_renewal`].
pub const CERT_RENEW_BEFORE_DAYS: i64 = 30;

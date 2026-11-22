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

pub const SELF_SIGNED_CERT_FILE: &str = "server.crt";
pub const SELF_SIGNED_KEY_FILE: &str = "server.key";
pub const IMPORTED_CERT_FILE: &str = "imported.crt";
pub const IMPORTED_KEY_FILE: &str = "imported.key";
pub const CERT_RENEW_BEFORE_DAYS: i64 = 30;

//! Certificate lifecycle health, mirroring `cert_health.go`.

use serde::{Deserialize, Serialize};

use super::CERT_RENEW_BEFORE_DAYS;

/// Lifecycle state of the certificate currently backing the encrypted listeners.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CertHealth {
    /// Whether certificate material was loaded successfully.
    pub loaded: bool,
    /// Whether the configured source is the service's own self-signed certificate.
    pub self_signed: bool,
    /// The certificate is past its `notAfter`.
    pub expired: bool,
    /// The certificate's `notBefore` is still in the future (usually a clock rollback).
    pub not_yet_valid: bool,
    /// The certificate expires inside the renewal window.
    pub expires_soon: bool,
    /// Whole days until expiry; negative once expired.
    pub days_remaining: i64,
    /// `notAfter` as Unix seconds (0 when nothing is loaded).
    pub not_after: i64,
}

impl CertHealth {
    /// Whether a self-signed certificate should be reissued.
    ///
    /// Imported certificates are never renewed here: replacing them with a self-signed certificate
    /// would hide an operator's configuration problem behind a certificate clients do not trust.
    pub fn needs_renewal(&self) -> bool {
        self.self_signed
            && (!self.loaded || self.expired || self.not_yet_valid || self.expires_soon)
    }
}

/// Whole days between `not_after` (Unix seconds) and `now`, truncating towards zero like Go's
/// `int(time.Until(notAfter).Hours() / 24)`.
pub(crate) fn days_remaining(not_after: i64, now: i64) -> i64 {
    (not_after - now) / 86_400
}

/// Seconds left until `not_after`, as computed by [`CERT_RENEW_BEFORE_DAYS`] windows.
pub(crate) fn within_renewal_window(not_after: i64, now: i64) -> bool {
    let remaining = not_after - now;
    remaining > 0 && remaining <= CERT_RENEW_BEFORE_DAYS * 86_400
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn needs_renewal_only_applies_to_self_signed_material() {
        let healthy = CertHealth {
            loaded: true,
            self_signed: true,
            ..Default::default()
        };
        assert!(!healthy.needs_renewal());

        let mut imported = CertHealth {
            self_signed: false,
            expired: true,
            ..Default::default()
        };
        assert!(!imported.needs_renewal());

        imported.self_signed = true;
        assert!(imported.needs_renewal());

        for health in [
            CertHealth {
                self_signed: true,
                loaded: false,
                ..Default::default()
            },
            CertHealth {
                self_signed: true,
                loaded: true,
                not_yet_valid: true,
                ..Default::default()
            },
            CertHealth {
                self_signed: true,
                loaded: true,
                expires_soon: true,
                ..Default::default()
            },
        ] {
            assert!(health.needs_renewal());
        }
    }

    #[test]
    fn day_math_truncates_towards_zero() {
        let now = 1_700_000_000;
        assert_eq!(days_remaining(now + 30 * 86_400, now), 30);
        assert_eq!(days_remaining(now + 86_399, now), 0);
        assert_eq!(days_remaining(now - 1, now), 0);
        assert_eq!(days_remaining(now - 86_401, now), -1);
    }

    #[test]
    fn renewal_window_is_thirty_days() {
        let now = 1_700_000_000;
        assert!(within_renewal_window(now + 86_400, now));
        assert!(within_renewal_window(
            now + CERT_RENEW_BEFORE_DAYS * 86_400,
            now
        ));
        assert!(!within_renewal_window(
            now + CERT_RENEW_BEFORE_DAYS * 86_400 + 1,
            now
        ));
        assert!(!within_renewal_window(now, now));
    }
}

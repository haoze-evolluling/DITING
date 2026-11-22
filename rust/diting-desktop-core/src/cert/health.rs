use serde::{Deserialize, Serialize};

use super::CERT_RENEW_BEFORE_DAYS;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CertHealth {
    pub loaded: bool,
    pub self_signed: bool,
    pub expired: bool,
    pub not_yet_valid: bool,
    pub expires_soon: bool,
    pub days_remaining: i64,
    pub not_after: i64,
}

impl CertHealth {
    pub fn needs_renewal(&self) -> bool {
        self.self_signed
            && (!self.loaded || self.expired || self.not_yet_valid || self.expires_soon)
    }
}

pub(crate) fn days_remaining(not_after: i64, now: i64) -> i64 {
    (not_after - now) / 86_400
}

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

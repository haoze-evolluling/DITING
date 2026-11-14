//! The leak verdict: one pure function over a normalized probe.
//!
//! `Probe` is what the caller already measured. Two independent signals feed the verdict:
//!
//! 1. **identity** — the resolver the fingerprint domain reported (`observed`) versus the one the
//!    configured upstream should report (`expected`). Both are normalized so a trailing dot or a
//!    case difference cannot flip the answer.
//! 2. **egress** — whether a plaintext 53/853 query left the device, or whether the query bypassed
//!    the tunnel entirely. Either is a positive leak regardless of identity.
//!
//! When nothing positive is observed but a signal is missing, the verdict is `unknown`: a failed
//! probe must not be reported as "passed".

/// The three-state verdict. Serialized as `pass` / `leak` / `unknown`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LeakStatus {
    Pass,
    Leak,
    Unknown,
}

impl LeakStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            LeakStatus::Pass => "pass",
            LeakStatus::Leak => "leak",
            LeakStatus::Unknown => "unknown",
        }
    }
}

/// A normalized fingerprint-probe outcome.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Probe {
    /// Resolver identity the fingerprint domain reported, when it answered.
    pub observed_exit_id: Option<String>,
    /// Resolver identity the configured upstream is expected to report.
    pub expected_exit_id: Option<String>,
    /// A plaintext 53/853 query was observed leaving un-proxied.
    pub plaintext_dns_seen: bool,
    /// The probe query left through the configured upstream. `None` when not measured.
    pub used_configured_upstream: Option<bool>,
}

/// The judgement plus a stable reason code the UI localizes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Verdict {
    pub status: LeakStatus,
    pub reason: String,
}

impl Verdict {
    fn new(status: LeakStatus, reason: &str) -> Self {
        Self {
            status,
            reason: reason.to_string(),
        }
    }

    pub fn is_leak(&self) -> bool {
        self.status == LeakStatus::Leak
    }
}

/// Lowercases, trims, and drops one trailing dot so `Example.COM.` and `example.com` compare equal.
fn normalize(identity: &str) -> String {
    identity.trim().trim_end_matches('.').to_ascii_lowercase()
}

/// `evaluate`: the leak judgement. Deterministic over its input.
pub fn evaluate(probe: &Probe) -> Verdict {
    // Egress signals win: a plaintext query or a bypassed upstream is a leak whatever identity says.
    if probe.plaintext_dns_seen {
        return Verdict::new(LeakStatus::Leak, "plaintext_dns_egress");
    }
    if probe.used_configured_upstream == Some(false) {
        return Verdict::new(LeakStatus::Leak, "bypass_upstream");
    }

    match (
        probe.observed_exit_id.as_deref(),
        probe.expected_exit_id.as_deref(),
    ) {
        (Some(observed), Some(expected)) if normalize(observed) == normalize(expected) => {
            Verdict::new(LeakStatus::Pass, "matches_configured_upstream")
        }
        (Some(_), Some(_)) => Verdict::new(LeakStatus::Leak, "exit_mismatch"),
        // No expected identity configured (e.g. a plain upstream) but the query provably did not
        // bypass the tunnel: treat as pass rather than unknown.
        (Some(_), None) if probe.used_configured_upstream == Some(true) => {
            Verdict::new(LeakStatus::Pass, "proxied_without_identity")
        }
        _ => Verdict::new(LeakStatus::Unknown, "insufficient_data"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn probe(observed: Option<&str>, expected: Option<&str>) -> Probe {
        Probe {
            observed_exit_id: observed.map(str::to_string),
            expected_exit_id: expected.map(str::to_string),
            ..Probe::default()
        }
    }

    #[test]
    fn matching_identity_passes() {
        let verdict = evaluate(&probe(Some("Alt-DNS.example."), Some("alt-dns.example")));
        assert_eq!(verdict.status, LeakStatus::Pass);
        assert_eq!(verdict.reason, "matches_configured_upstream");
    }

    #[test]
    fn differing_identity_leaks() {
        let verdict = evaluate(&probe(Some("isp-resolver"), Some("doh.example")));
        assert!(verdict.is_leak());
        assert_eq!(verdict.reason, "exit_mismatch");
    }

    #[test]
    fn plaintext_egress_is_a_leak_even_with_matching_identity() {
        let mut p = probe(Some("doh.example"), Some("doh.example"));
        p.plaintext_dns_seen = true;
        assert_eq!(evaluate(&p).reason, "plaintext_dns_egress");
    }

    #[test]
    fn bypassing_the_upstream_is_a_leak() {
        let mut p = probe(None, None);
        p.used_configured_upstream = Some(false);
        assert_eq!(evaluate(&p).reason, "bypass_upstream");
    }

    #[test]
    fn missing_signals_are_unknown_not_pass() {
        let verdict = evaluate(&Probe::default());
        assert_eq!(verdict.status, LeakStatus::Unknown);
        assert_eq!(verdict.reason, "insufficient_data");
    }

    #[test]
    fn proxied_without_expected_identity_passes() {
        let mut p = probe(Some("resolver"), None);
        p.used_configured_upstream = Some(true);
        assert_eq!(evaluate(&p).status, LeakStatus::Pass);
        assert_eq!(evaluate(&p).reason, "proxied_without_identity");
    }

    #[test]
    fn status_strings_are_stable() {
        assert_eq!(LeakStatus::Pass.as_str(), "pass");
        assert_eq!(LeakStatus::Leak.as_str(), "leak");
        assert_eq!(LeakStatus::Unknown.as_str(), "unknown");
    }
}

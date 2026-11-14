//! R4: temporary pause and allowlist-only resolution, shared by the DNS pipeline.
//!
//! Both are "light control" knobs the user expects to take effect immediately, so they live in the
//! engine's hot path as cheap flags rather than as edits to the rule snapshot. Keeping the decision
//! in one pure function means the DNS path stays readable and this logic is unit tested without a
//! live tunnel.
//!
//! * **Pause** — while paused every policy block is skipped, so DNS still resolves but nothing is
//!   filtered. The pause ends by wall clock, so no timer is required to "restore" blocking.
//! * **Allowlist-only** — a strict mode where a name that is not explicitly allow-listed is blocked
//!   even when no block rule matches. The policy already marks explicit allows with the
//!   `__ALLOW__` reason, so the distinction needs no extra snapshot data.

/// The `blocked_by` reason recorded for a name blocked only because allowlist-only is on.
pub const ALLOWLIST_ONLY_REASON: &str = "allowlist_only";

/// Resolve the final block decision for one policy verdict.
///
/// Returns `Some(reason)` when the query should be blocked (with the reason to log), or `None` to
/// forward it. `reason` is the policy's own reason (`__ALLOW__` for an explicit allow). A paused
/// engine never blocks; allowlist-only blocks anything that is not an explicit allow.
pub fn effective_block(
    blocked: bool,
    reason: &str,
    paused: bool,
    allowlist_only: bool,
) -> Option<String> {
    if paused {
        return None;
    }
    if blocked {
        return Some(reason.to_string());
    }
    if allowlist_only && reason != "__ALLOW__" {
        return Some(ALLOWLIST_ONLY_REASON.to_string());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_policy_block_is_kept_when_not_paused() {
        assert_eq!(
            effective_block(true, "ads.example", false, false).as_deref(),
            Some("ads.example")
        );
    }

    #[test]
    fn a_pause_suppresses_every_block() {
        assert_eq!(effective_block(true, "ads.example", true, false), None);
        // Allowlist-only is also suspended while paused: the user asked for no filtering at all.
        assert_eq!(effective_block(false, "", true, true), None);
    }

    #[test]
    fn allowlist_only_blocks_names_that_are_not_allowed() {
        assert_eq!(
            effective_block(false, "", false, true).as_deref(),
            Some(ALLOWLIST_ONLY_REASON)
        );
        // An explicit allow passes even in allowlist-only mode.
        assert_eq!(effective_block(false, "__ALLOW__", false, true), None);
    }

    #[test]
    fn a_normal_pass_is_forwarded() {
        assert_eq!(effective_block(false, "", false, false), None);
    }
}

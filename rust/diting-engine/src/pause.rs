pub const ALLOWLIST_ONLY_REASON: &str = "allowlist_only";

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
        assert_eq!(effective_block(false, "", true, true), None);
    }

    #[test]
    fn allowlist_only_blocks_names_that_are_not_allowed() {
        assert_eq!(
            effective_block(false, "", false, true).as_deref(),
            Some(ALLOWLIST_ONLY_REASON)
        );
        assert_eq!(effective_block(false, "__ALLOW__", false, true), None);
    }

    #[test]
    fn a_normal_pass_is_forwarded() {
        assert_eq!(effective_block(false, "", false, false), None);
    }
}

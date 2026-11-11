//! The three DNS cache presets, in one place.
//!
//! Each preset overwrites nine `dns_cache_*_v2` keys, so the numbers are a stored contract: the UI
//! offers three labels, but the values behind them must stay byte-identical to 1.4.3. Server mode
//! reuses the same three shapes with its own negative-TTL values.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CachePreset {
    Conservative = 0,
    Balanced = 1,
    HighHitRate = 2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CacheValues {
    pub mode: &'static str,
    pub max_ttl_seconds: i32,
    pub fixed_ttl_seconds: i32,
    pub min_ttl_enabled: bool,
    pub min_ttl_seconds: i32,
    pub stale_fallback_enabled: bool,
    pub stale_fallback_seconds: i32,
}

impl CachePreset {
    pub fn from_index(index: u8) -> Option<Self> {
        match index {
            0 => Some(CachePreset::Conservative),
            1 => Some(CachePreset::Balanced),
            2 => Some(CachePreset::HighHitRate),
            _ => None,
        }
    }

    /// The prefs spelling (`conservative` / `balanced` / `high_hit_rate`).
    pub fn storage_value(self) -> &'static str {
        match self {
            CachePreset::Conservative => "conservative",
            CachePreset::Balanced => "balanced",
            CachePreset::HighHitRate => "high_hit_rate",
        }
    }

    pub fn from_storage(value: &str) -> Option<Self> {
        match value {
            "conservative" => Some(CachePreset::Conservative),
            "balanced" => Some(CachePreset::Balanced),
            "high_hit_rate" => Some(CachePreset::HighHitRate),
            _ => None,
        }
    }

    pub fn values(self) -> CacheValues {
        match self {
            CachePreset::Conservative => CacheValues {
                mode: "follow_dns_ttl",
                max_ttl_seconds: 3600,
                fixed_ttl_seconds: 3600,
                min_ttl_enabled: false,
                min_ttl_seconds: 60,
                stale_fallback_enabled: false,
                stale_fallback_seconds: 300,
            },
            CachePreset::Balanced => CacheValues {
                mode: "limit_max_ttl",
                max_ttl_seconds: 3600,
                fixed_ttl_seconds: 3600,
                min_ttl_enabled: true,
                min_ttl_seconds: 60,
                stale_fallback_enabled: true,
                stale_fallback_seconds: 300,
            },
            CachePreset::HighHitRate => CacheValues {
                mode: "limit_max_ttl",
                max_ttl_seconds: 21600,
                fixed_ttl_seconds: 3600,
                min_ttl_enabled: true,
                min_ttl_seconds: 120,
                stale_fallback_enabled: true,
                stale_fallback_seconds: 900,
            },
        }
    }
}

/// The engine-side cache policy, read out of the raw keys.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CachePolicy {
    pub mode: String,
    pub max_ttl_seconds: i32,
    pub min_ttl_enabled: bool,
    pub min_ttl_seconds: i32,
    pub stale_fallback_enabled: bool,
    pub stale_fallback_seconds: i32,
}

/// `fromPolicy`: derive a preset from the raw keys so installs predating `dns_cache_preset_v3`
/// still show a sensible option.
pub fn from_policy(policy: &CachePolicy) -> CachePreset {
    if policy.mode == "follow_dns_ttl" && !policy.min_ttl_enabled && !policy.stale_fallback_enabled
    {
        return CachePreset::Conservative;
    }
    let balanced = CachePreset::Balanced.values();
    if policy.mode == "limit_max_ttl"
        && policy.max_ttl_seconds <= balanced.max_ttl_seconds
        && (!policy.min_ttl_enabled || policy.min_ttl_seconds <= balanced.min_ttl_seconds)
        && (!policy.stale_fallback_enabled
            || policy.stale_fallback_seconds <= balanced.stale_fallback_seconds)
    {
        return CachePreset::Balanced;
    }
    CachePreset::HighHitRate
}

/// `current`: the stored preset wins; a missing one is derived from the policy.
pub fn current(preset_raw: Option<&str>, policy: &CachePolicy) -> CachePreset {
    preset_raw
        .and_then(CachePreset::from_storage)
        .unwrap_or_else(|| from_policy(policy))
}

/// Server mode's cache document, by preset. The negative-TTL values differ from the tunnel's (they
/// belong to the standalone resolver), and an unknown spelling falls back to the balanced row.
pub fn server_cache_document(preset_raw: &str) -> (CacheValues, i32) {
    match CachePreset::from_storage(preset_raw) {
        Some(CachePreset::Conservative) => (CachePreset::Conservative.values(), 15),
        Some(CachePreset::HighHitRate) => (CachePreset::HighHitRate.values(), 60),
        _ => (CachePreset::Balanced.values(), 30),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy(
        mode: &str,
        max_ttl: i32,
        min_enabled: bool,
        min_ttl: i32,
        stale_enabled: bool,
        stale_ttl: i32,
    ) -> CachePolicy {
        CachePolicy {
            mode: mode.to_string(),
            max_ttl_seconds: max_ttl,
            min_ttl_enabled: min_enabled,
            min_ttl_seconds: min_ttl,
            stale_fallback_enabled: stale_enabled,
            stale_fallback_seconds: stale_ttl,
        }
    }

    #[test]
    fn preset_values_are_the_stored_contract() {
        assert_eq!(CachePreset::Conservative.values().mode, "follow_dns_ttl");
        assert!(!CachePreset::Conservative.values().min_ttl_enabled);
        let high = CachePreset::HighHitRate.values();
        assert_eq!(high.max_ttl_seconds, 21600);
        assert_eq!(high.min_ttl_seconds, 120);
        assert_eq!(high.stale_fallback_seconds, 900);
    }

    #[test]
    fn policy_derivation_matches_the_installs_that_predate_the_key() {
        assert_eq!(
            from_policy(&policy("follow_dns_ttl", 3600, false, 60, false, 300)),
            CachePreset::Conservative
        );
        assert_eq!(
            from_policy(&policy("limit_max_ttl", 1800, true, 30, false, 300)),
            CachePreset::Balanced
        );
        assert_eq!(
            from_policy(&policy("limit_max_ttl", 21600, true, 120, true, 900)),
            CachePreset::HighHitRate
        );
        assert_eq!(
            from_policy(&policy("limit_max_ttl", 5000, false, 60, false, 300)),
            CachePreset::HighHitRate
        );
    }

    #[test]
    fn stored_preset_wins_over_the_policy() {
        let stored = policy("follow_dns_ttl", 3600, false, 60, false, 300);
        assert_eq!(
            current(Some("high_hit_rate"), &stored),
            CachePreset::HighHitRate
        );
        assert_eq!(current(Some("nope"), &stored), CachePreset::Conservative);
        assert_eq!(current(None, &stored), CachePreset::Conservative);
    }

    #[test]
    fn server_mode_negative_ttls() {
        assert_eq!(server_cache_document("conservative").1, 15);
        assert_eq!(server_cache_document("high_hit_rate").1, 60);
        assert_eq!(server_cache_document("nope").1, 30);
        assert_eq!(
            server_cache_document("high_hit_rate").0.max_ttl_seconds,
            21600
        );
    }
}

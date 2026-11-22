#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CachePreset {
    Conservative,
    Balanced,
    HighHitRate,
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

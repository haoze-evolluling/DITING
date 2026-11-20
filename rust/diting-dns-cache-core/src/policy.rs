pub const NUM_SHARDS: usize = 64;

pub const DEFAULT_MAX_ENTRIES: usize = 4096;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TtlMode {
    FollowDnsTtl,
    LimitMaxTtl,
    FixedTtl,
    Default,
}

impl TtlMode {
    pub fn parse(raw: &[u8]) -> Self {
        let mut name = raw.to_vec();
        name.make_ascii_lowercase();
        match name.as_slice() {
            b"follow_dns_ttl" => TtlMode::FollowDnsTtl,
            b"limit_max_ttl" => TtlMode::LimitMaxTtl,
            b"fixed_ttl" => TtlMode::FixedTtl,
            _ => TtlMode::Default,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub enabled: bool,
    pub mode: TtlMode,
    pub max_ttl_seconds: i64,
    pub fixed_ttl_seconds: i64,
    pub min_ttl_enabled: bool,
    pub min_ttl_seconds: i64,
    pub stale_fallback_enabled: bool,
    pub stale_fallback_seconds: i64,
    pub negative_ttl_enabled: bool,
    pub negative_ttl_seconds: i64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            enabled: false,
            mode: TtlMode::Default,
            max_ttl_seconds: 0,
            fixed_ttl_seconds: 0,
            min_ttl_enabled: false,
            min_ttl_seconds: 0,
            stale_fallback_enabled: false,
            stale_fallback_seconds: 0,
            negative_ttl_enabled: false,
            negative_ttl_seconds: 0,
        }
    }
}

impl Config {
    pub fn normalized(mut self) -> Self {
        if self.max_ttl_seconds <= 0 {
            self.max_ttl_seconds = 3600;
        }
        if self.fixed_ttl_seconds <= 0 {
            self.fixed_ttl_seconds = 3600;
        }
        if self.min_ttl_seconds <= 0 {
            self.min_ttl_seconds = 60;
        }
        if self.stale_fallback_seconds <= 0 {
            self.stale_fallback_seconds = 300;
        }
        if self.negative_ttl_seconds <= 0 {
            self.negative_ttl_seconds = 30;
        }
        if !self.negative_ttl_enabled && self.enabled {
            self.negative_ttl_enabled = true;
        }
        self
    }

    pub fn effective_ttl(&self, upstream_ttl: u32) -> i64 {
        let mut ttl = i64::from(upstream_ttl);
        match self.mode {
            TtlMode::FollowDnsTtl => {}
            TtlMode::LimitMaxTtl | TtlMode::Default => {
                if self.max_ttl_seconds > 0 && ttl > self.max_ttl_seconds {
                    ttl = self.max_ttl_seconds;
                }
            }
            TtlMode::FixedTtl => {
                if self.fixed_ttl_seconds > 0 {
                    ttl = self.fixed_ttl_seconds;
                }
            }
        }
        if self.min_ttl_enabled && self.min_ttl_seconds > 0 && ttl < self.min_ttl_seconds {
            ttl = self.min_ttl_seconds;
        }
        if ttl <= 0 {
            0
        } else {
            ttl
        }
    }

    pub fn negative_ttl(&self, soa_ttl: u32, found: bool) -> i64 {
        let mut ttl = i64::from(soa_ttl);
        if !found || ttl <= 0 || (self.negative_ttl_seconds > 0 && ttl > self.negative_ttl_seconds)
        {
            ttl = self.negative_ttl_seconds;
        }
        if ttl <= 0 {
            ttl = 30;
        }
        ttl.clamp(5, 300)
    }

    pub fn flags(&self) -> u8 {
        let mut flags = 0u8;
        if self.enabled {
            flags |= FLAG_ENABLED;
        }
        if self.min_ttl_enabled {
            flags |= FLAG_MIN_TTL;
        }
        if self.stale_fallback_enabled {
            flags |= FLAG_STALE_FALLBACK;
        }
        if self.negative_ttl_enabled {
            flags |= FLAG_NEGATIVE_TTL;
        }
        flags
    }
}

pub const FLAG_ENABLED: u8 = 1 << 0;
pub const FLAG_MIN_TTL: u8 = 1 << 1;
pub const FLAG_STALE_FALLBACK: u8 = 1 << 2;
pub const FLAG_NEGATIVE_TTL: u8 = 1 << 3;

#[cfg(test)]
mod tests;

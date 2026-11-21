use std::sync::atomic::Ordering;
use std::sync::Arc;

use diting_gate_core::BlockedUids;

use crate::connection_limit::{BucketKind, Config as ConnectionLimitConfig, ConnectionLimiter};

use super::Engine;

impl Engine {
    pub fn set_rate_limit(&self, config: &diting_ratelimit_core::Config) {
        let limiter = if config.enabled {
            Some(diting_ratelimit_core::RateLimiter::new(config))
        } else {
            None
        };
        *self
            .rate_limit
            .write()
            .unwrap_or_else(|error| error.into_inner()) = limiter;
    }

    pub fn allow_client(&self, address: Option<&diting_ratelimit_core::Addr>, now_ns: i64) -> bool {
        match self
            .rate_limit
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            None => true,
            Some(limiter) => {
                limiter.allow(address, now_ns, diting_ratelimit_core::DEFAULT_MAX_BUCKETS)
            }
        }
    }

    pub fn set_connection_rate_limit(&self, config: ConnectionLimitConfig) {
        let limiter = config
            .enabled
            .then(|| Arc::new(ConnectionLimiter::new(config)));
        *self
            .connection_limit
            .write()
            .unwrap_or_else(|error| error.into_inner()) = limiter;
    }

    pub fn allow_connection_rate(&self, kind: BucketKind, uid: i32, now_ns: i64) -> bool {
        match self
            .connection_limit
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            None => true,
            Some(limiter) => limiter.allow(kind, uid, now_ns),
        }
    }

    pub fn set_filter_http3(&self, enabled: bool) {
        self.quic_drop.store(enabled, Ordering::Release);
    }

    pub fn filter_http3(&self) -> bool {
        self.quic_drop.load(Ordering::Acquire)
    }

    pub fn set_block_encrypted_dns(&self, enabled: bool) {
        self.block_encrypted_dns.store(enabled, Ordering::Release);
    }

    pub fn block_encrypted_dns(&self) -> bool {
        self.block_encrypted_dns.load(Ordering::Acquire)
    }

    pub fn set_blocked_uids(&self, csv: &str) {
        let parsed = Arc::new(BlockedUids::parse_csv(csv));
        *self
            .blocked_uids
            .write()
            .unwrap_or_else(|error| error.into_inner()) = parsed;
    }

    pub fn is_uid_blocked(&self, uid: i32) -> bool {
        if uid < 0 {
            return false;
        }
        self.blocked_uids
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .is_blocked(i64::from(uid))
    }
}

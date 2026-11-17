//! Cache lookup and store.
//!
//! A hit stops the walk; a stale hit is served immediately when optimistic mode is on and is kept
//! as a fallback otherwise. Excluded domains bypass both read and write, matching the Go comment:
//! skipping only one direction either keeps poison in the cache or makes the exclusion useless.
//! Responses produced by local stages never enter the cache because those stages stop earlier.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::cache::DesktopCache;
use diting_dns_wire::build::ParsedMessage;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::normalized_name;

pub struct CacheStage {
    cache: Arc<DesktopCache>,
}

impl CacheStage {
    pub fn new(cache: Arc<DesktopCache>) -> Self {
        Self { cache }
    }
}

#[async_trait]
impl Stage for CacheStage {
    fn name(&self) -> &'static str {
        "cache"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let settings = self.cache.settings();
        if !settings.enabled {
            return StageResult::Continue;
        }
        if self.cache.is_excluded(&normalized_name(&ctx.question.name)) {
            return StageResult::Continue;
        }
        let Some(hit) = self.cache.get(&ctx.request, &ctx.group) else {
            return StageResult::Continue;
        };
        if hit.stale {
            if settings.stale_fallback_enabled {
                ctx.stale_response = Some(hit.wire.clone());
            }
            if settings.optimistic && settings.stale_fallback_enabled {
                ctx.response = Some(hit.wire);
                ctx.set("cache_hit", "stale");
                return StageResult::Stop;
            }
            return StageResult::Continue;
        }
        ctx.response = Some(hit.wire);
        ctx.set("cache_hit", "fresh");
        StageResult::Stop
    }

    async fn after(&self, ctx: &mut DnsContext) {
        let settings = self.cache.settings();
        if !settings.enabled {
            return;
        }
        let excluded = self.cache.is_excluded(&normalized_name(&ctx.question.name));
        // A stale entry rescued the failed upstream path: serve it instead of SERVFAIL.
        let failed = ctx.response.is_none()
            || ctx
                .response
                .as_ref()
                .and_then(|wire| ParsedMessage::parse(wire))
                .map(|message| message.rcode() == 2)
                .unwrap_or(true);
        if failed {
            if let Some(stale) = ctx.stale_response.take() {
                if settings.stale_fallback_enabled {
                    ctx.response = Some(stale);
                    ctx.error = None;
                    ctx.set("cache_hit", "stale_fallback");
                    return;
                }
            }
            return;
        }
        if excluded || ctx.get("cache_hit") == Some("fresh") {
            return;
        }
        if let Some(response) = ctx.response.as_ref() {
            self.cache.put(&ctx.request, response, &ctx.group);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_core::cache::CacheSettings;
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord};

    fn cache() -> Arc<DesktopCache> {
        let mut settings = CacheSettings::default();
        settings.min_ttl_enabled = false;
        settings.max_ttl_seconds = 3600;
        Arc::new(DesktopCache::new(settings))
    }

    #[tokio::test]
    async fn store_then_hit_returns_the_cached_wire() {
        let cache = cache();
        let stage = CacheStage::new(cache.clone());
        let query = MessageBuilder::query("example.com", 1, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query.clone(), None, crate::context::Transport::Udp).unwrap();
        ctx.response = MessageBuilder::reply_to(&query)
            .unwrap()
            .push_answer(ResourceRecord::new(
                "example.com",
                1,
                1,
                60,
                RData::A("192.0.2.1".parse().unwrap()),
            ))
            .finish();
        stage.after(&mut ctx).await;
        let mut second =
            DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        assert_eq!(stage.before(&mut second).await, StageResult::Stop);
        assert_eq!(second.get("cache_hit"), Some("fresh"));
        assert!(second.response.is_some());
    }
}

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::cache::DesktopCache;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::normalized_name;

/// SERVFAIL 恒在 flags 的低 4 位；扩展 rcode 只用于大于 15 的取值。
const RCODE_SERVFAIL: u8 = 2;

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
        // 热路径只读这几个开关，用标量访问器而不是克隆整份 `CacheSettings`（含 Vec<String>）。
        if !self.cache.is_enabled() {
            return StageResult::Continue;
        }
        if self.cache.is_excluded(&normalized_name(&ctx.question.name)) {
            return StageResult::Continue;
        }
        let Some(hit) = self.cache.get(&ctx.request, &ctx.group) else {
            return StageResult::Continue;
        };
        if hit.stale {
            let fallback = self.cache.stale_fallback_enabled();
            if fallback {
                ctx.stale_response = Some(hit.wire.clone());
            }
            if fallback && self.cache.optimistic() {
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
        // 命中新鲜缓存时 `before` 已经直接给出应答，这里没有任何事可做。
        // 放到最前面，避免为了一个 `"fresh"` 判断白白解析整条响应报文。
        if ctx.get("cache_hit") == Some("fresh") {
            return;
        }
        if !self.cache.is_enabled() {
            return;
        }
        // 只想读 flags 里的 4 bit rcode，却用 `ParsedMessage::parse` 把整个报文
        // （每条 RR 的 owner name 与 rdata）解析一遍并全部丢弃。SERVFAIL 恒在低 4 位。
        let failed = match ctx.response.as_deref() {
            Some(wire) => diting_dns_wire::parse_header(wire)
                .map(|header| (header.flags & 0x000f) as u8 == RCODE_SERVFAIL)
                .unwrap_or(true),
            None => true,
        };
        if failed {
            if let Some(stale) = ctx.stale_response.take() {
                if self.cache.stale_fallback_enabled() {
                    ctx.response = Some(stale);
                    ctx.error = None;
                    ctx.set("cache_hit", "stale_fallback");
                    return;
                }
            }
            return;
        }
        if self.cache.is_excluded(&normalized_name(&ctx.question.name)) {
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
        let mut second = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        assert_eq!(stage.before(&mut second).await, StageResult::Stop);
        assert_eq!(second.get("cache_hit"), Some("fresh"));
        assert!(second.response.is_some());
    }
}

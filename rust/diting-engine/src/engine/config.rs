use std::sync::atomic::Ordering;
use std::sync::Arc;

use crate::config::DnsConfig;
use crate::error::EngineResult;
use crate::policy::rewrites_from_json;
use crate::resolver::{Resolver, ResolverDeps};

use super::{now_ms, Engine};

impl Engine {
    pub fn apply_dns_config(&self, payload: &str) -> EngineResult<()> {
        let config = DnsConfig::from_json(payload)?;

        self.cache.apply_policy(config.cache.clone());
        self.publish_resolver(&config);
        self.block_response
            .store(config.block_response, Ordering::Release);
        *self
            .blocked_qtypes
            .write()
            .unwrap_or_else(|error| error.into_inner()) = config.privacy.blocked_qtypes.clone();
        self.rebinding_protection
            .store(config.privacy.rebinding_protection, Ordering::Release);
        if let Err(error) = self.set_dns64(config.dns64, &[]) {
            self.log_error(&error);
        }
        self.set_rate_limit(&config.rate_limit);
        self.set_connection_rate_limit(config.connection_rate_limit);
        *self
            .dynamic_config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = config.dynamic_response;
        self.dynamic_blocks.reset();
        *self
            .config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Some(config);
        Ok(())
    }

    pub(super) fn publish_resolver(&self, config: &DnsConfig) {
        let deps = ResolverDeps {
            trust: self.upstream_trust(),
            bootstrap: Arc::clone(&self.bootstrap),
            stats: Arc::clone(&self.stats),
            protector: self.protector.clone(),
            outbound: Some(Arc::clone(&self.outbound)),
            system_dns: self.system_dns.clone(),
        };
        let resolver = Arc::new(Resolver::configured(config, deps));
        for reason in resolver.skipped() {
            self.log_error(reason);
        }
        let previous = std::mem::replace(
            &mut *self
                .resolver
                .write()
                .unwrap_or_else(|error| error.into_inner()),
            resolver,
        );
        previous.shutdown();
    }

    pub fn apply_rule_snapshot(&self, payload: &str) -> String {
        self.policy.apply(payload)
    }

    pub fn set_rewrite_rules(&self, payload: &str) {
        if payload.is_empty() {
            return;
        }
        match rewrites_from_json(payload) {
            Ok(entries) => self
                .rewrites
                .publish(diting_dns_core::RewriteTable::build(&entries)),
            Err(error) => self.log_error(&error),
        }
    }

    pub fn set_filter_dns(&self, enabled: bool) {
        self.filter_dns.store(enabled, Ordering::Release);
    }

    pub fn filter_dns(&self) -> bool {
        self.filter_dns.load(Ordering::Acquire)
    }

    pub fn set_block_ipv6(&self, enabled: bool) {
        self.block_ipv6.store(enabled, Ordering::Release);
    }

    pub fn block_ipv6(&self) -> bool {
        self.block_ipv6.load(Ordering::Acquire)
    }

    /// 仅影响允许 IPv6 时的 DNS 优先级：为真时对存在 AAAA 的域名压制 A。
    pub fn set_prefer_ipv6(&self, enabled: bool) {
        self.prefer_ipv6.store(enabled, Ordering::Release);
    }

    pub fn prefer_ipv6(&self) -> bool {
        self.prefer_ipv6.load(Ordering::Acquire)
    }

    /// 由 Android 侧在启动和网络切换时写入当前物理网络下发的 DNS。
    pub fn set_system_dns(&self, raw: &str) {
        self.system_dns.set(raw);
        self.system_dns.clear_degraded();
    }

    /// 网络切换后重建解析器：清空上游健康度、Bootstrap、DoT 与 DoH 连接池，
    /// 避免继续复用旧链路。新链路立即可用时，首轮查询短暂优先走系统 DNS。
    pub fn reset_resolver_health(&self) {
        self.negative.clear();
        let config = self
            .config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        // 重建解析器会一并丢弃 DoH 长连接池；仅重置统计无法断开旧连接。
        if let Some(config) = config {
            self.publish_resolver(&config);
        }
        // ProviderStats 是引擎级共享实例，重建后仍需显式清零熔断与 RTT。
        self.resolver().reset_health();
        self.system_dns.mark_degraded(crate::resolver::now_ns());
    }

    pub fn negative_cache(&self) -> &crate::dns::negative::NegativeCache {
        &self.negative
    }

    pub fn records_blocked(&self, qtype: u16) -> bool {
        self.blocked_qtypes
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .contains(&qtype)
    }

    pub fn rebinding_protection(&self) -> bool {
        self.rebinding_protection.load(Ordering::Acquire)
    }

    pub fn set_dns64(&self, enabled: bool, prefixes: &[String]) -> Result<(), String> {
        let engine = if enabled {
            Some(Arc::new(
                diting_dns64_core::Engine::new(true, prefixes)
                    .map_err(|error| format!("dns64 prefix rejected: {error:?}"))?,
            ))
        } else {
            None
        };
        *self
            .dns64
            .write()
            .unwrap_or_else(|error| error.into_inner()) = engine;
        Ok(())
    }

    pub fn dns64(&self) -> Option<Arc<diting_dns64_core::Engine>> {
        self.dns64
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn set_block_pause_until(&self, until_ms: i64) {
        self.pause_until_ms.store(until_ms, Ordering::Release);
    }

    pub fn block_paused(&self) -> bool {
        let until = self.pause_until_ms.load(Ordering::Acquire);
        until > 0 && now_ms() < until
    }

    pub fn block_pause_until(&self) -> i64 {
        self.pause_until_ms.load(Ordering::Acquire)
    }

    pub fn set_allowlist_only(&self, enabled: bool) {
        self.allowlist_only.store(enabled, Ordering::Release);
    }

    pub fn allowlist_only(&self) -> bool {
        self.allowlist_only.load(Ordering::Acquire)
    }

    pub fn set_block_response_type(&self, response_type: &str) {
        let parsed = diting_config_core::protocol::parse_response_type(response_type).code() as u32;
        self.block_response.store(parsed, Ordering::Release);
    }

    pub fn clear_dns_cache(&self) {
        self.cache.clear();
    }

    pub fn effective_block_response(&self, domain: &str) -> u32 {
        let fallback = self.block_response.load(Ordering::Acquire);
        let config = *self
            .dynamic_config
            .read()
            .unwrap_or_else(|error| error.into_inner());
        if !config.enabled {
            return fallback;
        }
        let clean = diting_config_core::rewrite::normalize_domain(domain);
        if clean.is_empty() {
            return fallback;
        }
        self.dynamic_blocks
            .response_for(&clean, &config, fallback, crate::resolver::now_ns())
    }

    pub fn cache_config(&self) -> diting_dns_cache_core::policy::Config {
        self.cache.policy()
    }

    pub fn dns_config(&self) -> Option<DnsConfig> {
        self.config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }
}

use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use diting_desktop_core::filter::RuleEngine;
use diting_desktop_core::resolver::DesktopResolver;
use diting_desktop_core::safebrowsing::SafeBrowsingEngine;
use diting_dns_wire::build::{MessageBuilder, ParsedMessage, RData};
use diting_dns_wire::{TYPE_A, TYPE_AAAA, TYPE_HTTPS, TYPE_SVCB};

use diting_safebrowsing_core::engine::{SERVICE_PARENTAL_CONTROL, SERVICE_SAFE_BROWSING};
use diting_safebrowsing_core::hash::parse_txt_hashes;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::block::respond_blocked;
use crate::stages::util::normalized_name;

pub struct SafeBrowsingStage {
    engine: Arc<SafeBrowsingEngine>,
    resolver: Arc<DesktopResolver>,
    filter: RuleEngine,
}

impl SafeBrowsingStage {
    pub fn new(
        engine: Arc<SafeBrowsingEngine>,
        resolver: Arc<DesktopResolver>,
        filter: RuleEngine,
    ) -> Self {
        Self {
            engine,
            resolver,
            filter,
        }
    }
}

#[async_trait]
impl Stage for SafeBrowsingStage {
    fn name(&self) -> &'static str {
        "safebrowsing"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let config = self.engine.config();
        if !config.enabled || !is_connectable(ctx.question.qtype) {
            return StageResult::Continue;
        }
        let domain = normalized_name(&ctx.question.name);
        if domain.is_empty() {
            return StageResult::Continue;
        }
        let kernel = self.engine.engine();
        let services: &[u8] = if config.parental_enabled {
            &[SERVICE_SAFE_BROWSING, SERVICE_PARENTAL_CONTROL]
        } else {
            &[SERVICE_SAFE_BROWSING]
        };
        for service in services {
            let Some(plan) = kernel.plan(*service, &domain, now_ms()) else {
                return StageResult::Continue;
            };
            if plan.empty {
                return StageResult::Continue;
            }
            if plan.found {
                self.engine.record(true, plan.blocked);
                if plan.blocked {
                    return self.block(ctx, service_name(*service));
                }
                continue;
            }
            let Some(query) = MessageBuilder::query(&plan.question, TYPE_A, 1).finish() else {
                continue;
            };
            let timeout = Duration::from_millis(config.timeout_ms.max(100) as u64);
            let response = match tokio::time::timeout(
                timeout,
                self.resolver.resolve(&query, &ctx.group),
            )
            .await
            {
                Ok(Ok(response)) => response,
                _ => {
                    self.engine.record_failure();
                    ctx.set("safebrowsing_failed", "true");
                    ctx.set("safebrowsing_service", service_name(*service));
                    return StageResult::Continue;
                }
            };
            let Some(message) = ParsedMessage::parse(&response) else {
                self.engine.record_failure();
                ctx.set("safebrowsing_failed", "true");
                return StageResult::Continue;
            };
            let texts: Vec<String> = message
                .answers
                .iter()
                .filter_map(|record| match &record.rdata {
                    RData::Txt(values) => Some(
                        values
                            .iter()
                            .map(|value| String::from_utf8_lossy(value).into_owned())
                            .collect::<Vec<_>>(),
                    ),
                    _ => None,
                })
                .flatten()
                .collect();
            let received = parse_txt_hashes(&texts);
            let blocked = kernel.apply(*service, &plan.need_query, &received, now_ms());
            self.engine.record(false, blocked);
            if blocked {
                return self.block(ctx, service_name(*service));
            }
        }
        StageResult::Continue
    }
}

impl SafeBrowsingStage {
    fn block(&self, ctx: &mut DnsContext, service: &str) -> StageResult {
        let policy = self.filter.block_response_config(&ctx.group);
        respond_blocked(ctx, &policy);
        ctx.set("source", "safebrowsing");
        ctx.set("cache_hit", "safebrowsing");
        ctx.set("filter_action", "block");
        ctx.set("filter_blocked", "true");
        ctx.set(
            "filter_rule",
            normalized_name(&ctx.question.name).into_owned(),
        );
        ctx.set("filter_reason", service);
        ctx.set("filter_list", service);
        StageResult::Stop
    }
}

fn service_name(service: u8) -> &'static str {
    if service == SERVICE_PARENTAL_CONTROL {
        "parental_control"
    } else {
        "safe_browsing"
    }
}

fn is_connectable(qtype: u16) -> bool {
    matches!(qtype, TYPE_A | TYPE_AAAA | TYPE_HTTPS | TYPE_SVCB)
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

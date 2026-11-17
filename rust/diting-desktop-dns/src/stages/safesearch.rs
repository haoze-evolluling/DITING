//! Forced safe search.
//!
//! Search-engine names are answered with the provider's enforced CNAME/IP. A matched name whose
//! query type has no rule (e.g. AAAA for a CNAME-only provider) is authoritative NODATA so the
//! client cannot fall back to the unfiltered address through another query type.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::safesearch::SafeSearchEngine;
use diting_dns_wire::build::{RData, ResourceRecord, TYPE_A, TYPE_AAAA};
use diting_dns_wire::CLASS_IN;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{normalized_name, respond, start_reply};

pub struct SafeSearchStage {
    engine: Arc<SafeSearchEngine>,
}

impl SafeSearchStage {
    pub fn new(engine: Arc<SafeSearchEngine>) -> Self {
        Self { engine }
    }
}

#[async_trait]
impl Stage for SafeSearchStage {
    fn name(&self) -> &'static str {
        "safesearch"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.engine.enabled() {
            return StageResult::Continue;
        }
        let domain = normalized_name(&ctx.question.name);
        if domain.is_empty() {
            return StageResult::Continue;
        }
        let Some(result) = self.engine.lookup(&domain, ctx.question.qtype) else {
            return StageResult::Continue;
        };
        let ttl = self.engine.stats().ttl;
        let Some(mut builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        if !result.cname.is_empty() {
            builder = builder.push_answer(ResourceRecord::new(
                &ctx.question.name,
                diting_dns_wire::TYPE_CNAME,
                CLASS_IN,
                ttl,
                RData::Cname(result.cname.clone()),
            ));
        } else if let Some(ip) = result.ip {
            if result.ip_type == ctx.question.qtype {
                let rdata = match (result.ip_type, ip) {
                    (TYPE_A, std::net::IpAddr::V4(ip)) => RData::A(ip),
                    (TYPE_AAAA, std::net::IpAddr::V6(ip)) => RData::Aaaa(ip),
                    (TYPE_A, std::net::IpAddr::V6(ip)) => RData::A(match ip.to_ipv4_mapped() {
                        Some(v4) => v4,
                        None => std::net::Ipv4Addr::UNSPECIFIED,
                    }),
                    _ => return StageResult::Continue,
                };
                builder = builder.push_answer(ResourceRecord::new(
                    &ctx.question.name,
                    result.ip_type,
                    CLASS_IN,
                    ttl,
                    rdata,
                ));
            } else {
                return StageResult::Continue;
            }
        } else if !result.nodata {
            return StageResult::Continue;
        }
        respond(ctx, builder);
        ctx.set("source", "safesearch");
        ctx.set("cache_hit", "safesearch");
        ctx.set("safesearch_service", result.service);
        StageResult::Stop
    }
}

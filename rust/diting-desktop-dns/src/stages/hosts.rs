//! Local hosts-file authority.
//!
//! A name present in hosts but without the queried record type gets an authoritative NODATA:
//! forwarding an internal name to a public resolver leaks the name and often returns an ISP page.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::hosts::HostsResolver;
use diting_dns_wire::build::{RData, ResourceRecord, TYPE_A, TYPE_AAAA, TYPE_PTR};
use diting_dns_wire::CLASS_IN;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{normalized_name, respond, start_reply};

pub struct HostsStage {
    hosts: Arc<HostsResolver>,
}

impl HostsStage {
    pub fn new(hosts: Arc<HostsResolver>) -> Self {
        Self { hosts }
    }
}

#[async_trait]
impl Stage for HostsStage {
    fn name(&self) -> &'static str {
        "hosts"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.hosts.enabled() {
            return StageResult::Continue;
        }
        let domain = normalized_name(&ctx.question.name);
        if domain.is_empty() {
            return StageResult::Continue;
        }
        if ctx.question.qtype == TYPE_PTR {
            let names = self.hosts.ptr(&ctx.question.name);
            if names.is_empty() {
                return StageResult::Continue;
            }
            let Some(mut builder) = start_reply(ctx) else {
                return StageResult::Fail("空查询报文".to_string());
            };
            for name in names {
                builder = builder.push_answer(ResourceRecord::new(
                    &ctx.question.name,
                    TYPE_PTR,
                    CLASS_IN,
                    self.hosts.ttl(),
                    RData::Ptr(crate::stages::util::normalize_trailing_dot(&name)),
                ));
            }
            respond(ctx, builder);
            ctx.set("source", "hosts");
            ctx.set("cache_hit", "hosts");
            return StageResult::Stop;
        }
        if ctx.question.qtype != TYPE_A && ctx.question.qtype != TYPE_AAAA {
            return StageResult::Continue;
        }
        let records = self.hosts.lookup(&domain, ctx.question.qtype);
        if records.is_empty() {
            if self.hosts.has_domain(&domain) {
                let Some(builder) = start_reply(ctx) else {
                    return StageResult::Fail("空查询报文".to_string());
                };
                respond(ctx, builder);
                ctx.set("source", "hosts");
                ctx.set("cache_hit", "hosts_nodata");
                return StageResult::Stop;
            }
            return StageResult::Continue;
        }
        let Some(mut builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        for record in records {
            let rdata = match record.ip {
                std::net::IpAddr::V4(ip) => RData::A(ip),
                std::net::IpAddr::V6(ip) => RData::Aaaa(ip),
            };
            builder = builder.push_answer(ResourceRecord::new(
                &record.owner,
                record.qtype,
                CLASS_IN,
                record.ttl,
                rdata,
            ));
        }
        respond(ctx, builder);
        ctx.set("source", "hosts");
        ctx.set("cache_hit", "hosts");
        StageResult::Stop
    }
}

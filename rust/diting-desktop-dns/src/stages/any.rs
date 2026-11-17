//! RFC 8482 ANY minimization.
//!
//! ANY queries are an amplification vector and they defeat type-specific blocklists (asking ANY
//! returns both A and AAAA). Two legal answers exist: NOTIMP, or NOERROR + HINFO "RFC8482". The
//! mode is read per query so a configuration change applies without rebuilding the pipeline.

use std::sync::Arc;

use async_trait::async_trait;
use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord, TYPE_ANY, TYPE_HINFO};
use diting_dns_wire::CLASS_IN;

use crate::context::{DnsContext, RCODE_NOTIMP};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{respond, start_reply};
use crate::stages::ConfigHandle;

pub const RFC8482_HINFO: &str = "RFC8482";

pub struct AnyStage {
    config: ConfigHandle,
}

impl AnyStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for AnyStage {
    fn name(&self) -> &'static str {
        "any"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let (enabled, mode) = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            (config.dns.block_any, config.dns.block_any_mode.clone())
        };
        if !enabled || ctx.question.qtype != TYPE_ANY || ctx.question.qclass != CLASS_IN {
            return StageResult::Continue;
        }
        let Some(mut builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        if mode.trim().eq_ignore_ascii_case("rfc8482") {
            builder = builder.push_answer(ResourceRecord::new(
                &ctx.question.name,
                TYPE_HINFO,
                CLASS_IN,
                0,
                RData::Hinfo {
                    cpu: RFC8482_HINFO.to_string(),
                    os: String::new(),
                },
            ));
        } else {
            builder = builder.set_rcode(RCODE_NOTIMP);
        }
        respond(ctx, builder);
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", "BLOCK_ANY");
        ctx.set("filter_reason", "ANY query minimized per RFC 8482");
        ctx.set("any_blocked", "true");
        StageResult::Stop
    }
}

/// Kept for the pipeline assembly and tests: builds the minimal answer directly.
pub fn minimal_response(query: &[u8], mode: &str) -> Option<Vec<u8>> {
    let mut message =
        crate::context::DnsContext::new(query.to_vec(), None, crate::context::Transport::Udp)?;
    let builder = MessageBuilder::reply_to(&message.request)?
        .set_authoritative(true)
        .set_recursion_available(true);
    let builder = if mode.trim().eq_ignore_ascii_case("rfc8482") {
        builder.push_answer(ResourceRecord::new(
            &message.question.name,
            TYPE_HINFO,
            CLASS_IN,
            0,
            RData::Hinfo {
                cpu: RFC8482_HINFO.to_string(),
                os: String::new(),
            },
        ))
    } else {
        builder.set_rcode(RCODE_NOTIMP)
    };
    message.response = builder.finish();
    message.response
}

/// Shared with the pipeline builder so tests do not construct a stage for a one-shot check.
pub fn shared_config(config: ConfigHandle) -> Arc<dyn Stage> {
    Arc::new(AnyStage::new(config))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::Transport;

    fn query(qtype: u16) -> Vec<u8> {
        MessageBuilder::query("example.com", qtype, 1)
            .finish()
            .unwrap()
    }

    #[tokio::test]
    async fn notimp_mode_is_default() {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        config.write().unwrap().dns.block_any = true;
        let stage = AnyStage::new(config);
        let mut ctx = DnsContext::new(query(TYPE_ANY), None, Transport::Udp).unwrap();
        assert_eq!(stage.before(&mut ctx).await, StageResult::Stop);
        let response = ctx.response.unwrap();
        let header = diting_dns_wire::parse_header(&response).unwrap();
        assert_eq!((header.flags & 0x0f) as u8, RCODE_NOTIMP);
    }

    #[test]
    fn rfc8482_returns_hinfo() {
        let response = minimal_response(&query(TYPE_ANY), "RFC8482").unwrap();
        let message = diting_dns_wire::build::ParsedMessage::parse(&response).unwrap();
        assert_eq!(message.answers.len(), 1);
        assert_eq!(message.answers[0].rdata.rtype(), Some(TYPE_HINFO));
    }
}

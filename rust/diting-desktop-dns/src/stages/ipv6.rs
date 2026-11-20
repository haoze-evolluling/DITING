use async_trait::async_trait;
use diting_dns_wire::build::ParsedMessage;
use diting_dns_wire::TYPE_AAAA;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{negative_soa, respond, start_reply, strip_ipv6_hints};
use crate::stages::ConfigHandle;

pub struct Ipv6Stage {
    config: ConfigHandle,
}

impl Ipv6Stage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for Ipv6Stage {
    fn name(&self) -> &'static str {
        "ipv6"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.enabled() {
            return StageResult::Continue;
        }
        if ctx.question.qtype != TYPE_AAAA {
            return StageResult::Continue;
        }
        let Some(builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        let zone = crate::stages::util::normalize_trailing_dot(&ctx.question.name);
        respond(ctx, builder.push_authority(negative_soa(&zone, 300)));
        ctx.set("source", "block_ipv6");
        ctx.set("ipv6_blocked", "true");
        StageResult::Stop
    }

    async fn after(&self, ctx: &mut DnsContext) {
        if !self.enabled() {
            return;
        }
        let Some(response) = ctx.response.take() else {
            return;
        };
        let Some(mut message) = ParsedMessage::parse(&response) else {
            ctx.response = Some(response);
            return;
        };
        if !strip_ipv6_hints(&mut message) {
            ctx.response = Some(response);
            return;
        }
        ctx.response = message.to_wire();
        ctx.set("ipv6_hints_stripped", "true");
    }
}

impl Ipv6Stage {
    fn enabled(&self) -> bool {
        self.config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .dns
            .block_ipv6
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord, SvcParam, SvcbRData};
    use diting_dns_wire::TYPE_HTTPS;

    fn config(enabled: bool) -> ConfigHandle {
        let handle = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        handle.write().unwrap().dns.block_ipv6 = enabled;
        handle
    }

    #[tokio::test]
    async fn aaaa_queries_get_authoritative_nodata() {
        let stage = Ipv6Stage::new(config(true));
        let query = MessageBuilder::query("example.com", TYPE_AAAA, 1)
            .finish()
            .unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        assert_eq!(stage.before(&mut ctx).await, StageResult::Stop);
        let message = ParsedMessage::parse(ctx.response.as_ref().unwrap()).unwrap();
        assert_eq!(message.rcode(), 0);
        assert_eq!(message.authorities.len(), 1);
    }

    #[tokio::test]
    async fn https_answers_lose_ipv6_hints() {
        let stage = Ipv6Stage::new(config(true));
        let query = MessageBuilder::query("example.com", TYPE_HTTPS, 1)
            .finish()
            .unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        let svcb =
            SvcbRData::new(1, ".").push(SvcParam::ipv6hint(&["2001:db8::1".parse().unwrap()]));
        ctx.response = MessageBuilder::reply_to(&ctx.request)
            .unwrap()
            .push_answer(ResourceRecord::new(
                "example.com",
                TYPE_HTTPS,
                1,
                60,
                RData::Https(svcb),
            ))
            .finish();
        stage.after(&mut ctx).await;
        let message = ParsedMessage::parse(ctx.response.as_ref().unwrap()).unwrap();
        let RData::Https(svcb) = &message.answers[0].rdata else {
            panic!("expected HTTPS");
        };
        assert!(svcb.params.is_empty());
    }
}

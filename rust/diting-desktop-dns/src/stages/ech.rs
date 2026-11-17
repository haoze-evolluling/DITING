//! Encrypted Client Hello parameter stripping (RFC 9460 §6.3).
//!
//! When ECH is advertised in DNS, a client can complete a TLS handshake to a name the local
//! policy never gets to see. Removing the `ech` SvcParam from HTTPS/SVCB answers forces a
//! visible SNI. The stage runs as a postlude because the parameter arrives in the upstream (or
//! cached) answer.

use async_trait::async_trait;
use diting_dns_wire::build::ParsedMessage;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::strip_ech;
use crate::stages::ConfigHandle;

pub struct EchStage {
    config: ConfigHandle,
}

impl EchStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for EchStage {
    fn name(&self) -> &'static str {
        "ech"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        let enabled = self
            .config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .dns
            .block_ech;
        if !enabled {
            return;
        }
        let Some(response) = ctx.response.take() else {
            return;
        };
        let Some(mut message) = ParsedMessage::parse(&response) else {
            ctx.response = Some(response);
            return;
        };
        if !strip_ech(&mut message) {
            ctx.response = Some(response);
            return;
        }
        ctx.response = message.to_wire();
        ctx.set("ech_stripped", "true");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord, SvcParam, SvcbRData};
    use diting_dns_wire::TYPE_HTTPS;

    #[tokio::test]
    async fn ech_is_removed_from_answers() {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        config.write().unwrap().dns.block_ech = true;
        let stage = EchStage::new(config);
        let query = MessageBuilder::query("example.com", 1, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        let svcb = SvcbRData::new(1, ".").push(SvcParam::new(5, vec![0xde, 0xad]));
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
        assert_eq!(ctx.get("ech_stripped"), Some("true"));
    }
}

use async_trait::async_trait;
use diting_dns_wire::build::{RData, ResourceRecord, TYPE_A, TYPE_AAAA};
use diting_dns_wire::CLASS_IN;

use crate::context::{DnsContext, RCODE_NXDOMAIN};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{normalized_name, respond, start_reply};

pub struct SudnStage;

#[async_trait]
impl Stage for SudnStage {
    fn name(&self) -> &'static str {
        "sudn"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let name = normalized_name(&ctx.question.name);
        if name.is_empty() {
            return StageResult::Continue;
        }
        if name == "localhost" || name.ends_with(".localhost") {
            let Some(mut builder) = start_reply(ctx) else {
                return StageResult::Fail("空查询报文".to_string());
            };
            match ctx.question.qtype {
                TYPE_A => {
                    builder = builder.push_answer(ResourceRecord::new(
                        &ctx.question.name,
                        TYPE_A,
                        CLASS_IN,
                        300,
                        RData::A(std::net::Ipv4Addr::LOCALHOST),
                    ));
                }
                TYPE_AAAA => {
                    builder = builder.push_answer(ResourceRecord::new(
                        &ctx.question.name,
                        TYPE_AAAA,
                        CLASS_IN,
                        300,
                        RData::Aaaa(std::net::Ipv6Addr::LOCALHOST),
                    ));
                }
                _ => {}
            }
            respond(ctx, builder);
            ctx.set("sudn_handled", "true");
            ctx.set("source", "sudn");
            return StageResult::Stop;
        }
        if matches_suffix(&name, "test")
            || matches_suffix(&name, "invalid")
            || matches_suffix(&name, "onion")
            || matches_suffix(&name, "home.arpa")
        {
            let Some(builder) = start_reply(ctx) else {
                return StageResult::Fail("空查询报文".to_string());
            };
            respond(ctx, builder.set_rcode(RCODE_NXDOMAIN));
            ctx.set("sudn_handled", "true");
            ctx.set("source", "sudn");
            return StageResult::Stop;
        }
        if matches_suffix(&name, "resolver.arpa") {
            let Some(builder) = start_reply(ctx) else {
                return StageResult::Fail("空查询报文".to_string());
            };
            respond(ctx, builder);
            ctx.set("sudn_handled", "true");
            ctx.set("source", "sudn_ddr");
            return StageResult::Stop;
        }
        StageResult::Continue
    }
}

fn matches_suffix(name: &str, suffix: &str) -> bool {
    crate::stages::util::domain_or_suffix(name, suffix)
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::MessageBuilder;

    async fn answer(name: &str, qtype: u16) -> Option<Vec<u8>> {
        let query = MessageBuilder::query(name, qtype, 1).finish().unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        let result = SudnStage.before(&mut ctx).await;
        (result == StageResult::Stop).then(|| ctx.response.unwrap())
    }

    #[tokio::test]
    async fn localhost_is_answered_locally() {
        let response = answer("foo.localhost", TYPE_A).await.unwrap();
        let message = diting_dns_wire::build::ParsedMessage::parse(&response).unwrap();
        assert_eq!(message.answers.len(), 1);
    }

    #[tokio::test]
    async fn special_names_are_negative_or_nodata() {
        for name in ["test", "a.test", "invalid", "x.onion", "home.arpa"] {
            let response = answer(name, TYPE_A).await.unwrap();
            let header = diting_dns_wire::parse_header(&response).unwrap();
            assert_eq!((header.flags & 0x0f) as u8, RCODE_NXDOMAIN, "{name}");
        }
        let response = answer("_dns.resolver.arpa", 64).await.unwrap();
        let header = diting_dns_wire::parse_header(&response).unwrap();
        assert_eq!(header.flags & 0x0f, 0);
        assert_eq!(header.answer_count, 0);
    }

    #[tokio::test]
    async fn ordinary_names_pass_through() {
        assert!(answer("example.com", TYPE_A).await.is_none());
    }
}

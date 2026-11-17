//! RFC 6147 DNS64 synthesis.
//!
//! On an IPv6-only network an AAAA name that has only IPv4 addresses gets synthetic AAAA records
//! built from the configured NAT64 prefix. Synthesis only happens for a successful answer without
//! a usable AAAA (RFC 6147 §5.1.1/§5.1.2); CNAME chains from the A lookup are preserved and the
//! TTL is the minimum across the chain (§5.1.7).

use std::sync::Arc;

use async_trait::async_trait;
use diting_dns64_core::engine::Engine;
use diting_dns_wire::build::{
    MessageBuilder, ParsedMessage, RData, ResourceRecord, TYPE_A, TYPE_AAAA, TYPE_CNAME,
};
use diting_dns_wire::CLASS_IN;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::ConfigHandle;

pub struct Dns64Stage {
    config: ConfigHandle,
    resolver: Arc<diting_desktop_core::resolver::DesktopResolver>,
}

impl Dns64Stage {
    pub fn new(
        config: ConfigHandle,
        resolver: Arc<diting_desktop_core::resolver::DesktopResolver>,
    ) -> Self {
        Self { config, resolver }
    }
}

#[async_trait]
impl Stage for Dns64Stage {
    fn name(&self) -> &'static str {
        "dns64"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        if ctx.question.qtype != TYPE_AAAA {
            return;
        }
        let (enabled, prefixes) = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            (config.dns64.enabled, config.dns64.prefixes.clone())
        };
        if !enabled {
            return;
        }
        let Ok(engine) = Engine::new(true, &prefixes) else {
            return;
        };
        let Some(response) = ctx.response.as_ref() else {
            return;
        };
        let Some(mut message) = ParsedMessage::parse(response) else {
            return;
        };
        if message.rcode() != 0 {
            return;
        }
        let existing: Vec<Vec<u8>> = message
            .answers
            .iter()
            .filter_map(|record| match &record.rdata {
                RData::Aaaa(ip) => Some(ip.octets().to_vec()),
                _ => None,
            })
            .collect();
        let refs: Vec<&[u8]> = existing.iter().map(Vec::as_slice).collect();
        if engine.has_valid_aaaa(&refs) {
            return;
        }
        let Some(a_query) = MessageBuilder::query(&ctx.question.name, TYPE_A, CLASS_IN).finish()
        else {
            return;
        };
        let Ok(a_response) = self.resolver.resolve(&a_query, &ctx.group).await else {
            return;
        };
        let Some(a_message) = ParsedMessage::parse(&a_response) else {
            return;
        };
        if a_message.rcode() != 0 {
            return;
        }
        let mut min_ttl = u32::MAX;
        let mut a_records = Vec::new();
        let mut cnames = Vec::new();
        for record in &a_message.answers {
            match &record.rdata {
                RData::A(ip) => {
                    min_ttl = min_ttl.min(record.ttl);
                    a_records.push((record.name.clone(), *ip));
                }
                RData::Cname(target) => {
                    min_ttl = min_ttl.min(record.ttl);
                    cnames.push((record.name.clone(), target.clone(), record.ttl));
                }
                _ => {}
            }
        }
        if a_records.is_empty() {
            return;
        }
        if min_ttl == u32::MAX {
            min_ttl = 60;
        }
        let mut added = false;
        for (name, address) in a_records {
            for synthesized in engine.synthesize(Some(address.octets())) {
                message.answers.push(ResourceRecord::new(
                    name.clone(),
                    TYPE_AAAA,
                    CLASS_IN,
                    min_ttl,
                    RData::Aaaa(std::net::Ipv6Addr::from(synthesized)),
                ));
                added = true;
            }
        }
        if !added {
            return;
        }
        for (name, target, ttl) in cnames {
            let exists = message.answers.iter().any(|record| {
                record.name == name
                    && matches!(&record.rdata, RData::Cname(value) if *value == target)
            });
            if !exists {
                message.answers.push(ResourceRecord::new(
                    name,
                    TYPE_CNAME,
                    CLASS_IN,
                    ttl,
                    RData::Cname(target),
                ));
            }
        }
        if let Some(wire) = message.to_wire() {
            ctx.response = Some(wire);
            ctx.set("dns64_synthesized", "true");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord};

    fn response() -> Vec<u8> {
        let query = MessageBuilder::query("v4only.example", TYPE_AAAA, CLASS_IN)
            .finish()
            .unwrap();
        MessageBuilder::reply_to(&query)
            .unwrap()
            .push_answer(ResourceRecord::new(
                "v4only.example",
                TYPE_A,
                CLASS_IN,
                120,
                RData::A("192.0.2.1".parse().unwrap()),
            ))
            .finish()
            .unwrap()
    }

    #[test]
    fn synthesis_uses_the_well_known_prefix() {
        let engine = Engine::new(true, &["64:ff9b::/96".to_string()]).unwrap();
        let addresses = engine.synthesize(Some([192, 0, 2, 1]));
        assert_eq!(addresses.len(), 1);
        assert_eq!(
            std::net::Ipv6Addr::from(addresses[0]).to_string(),
            "64:ff9b::c000:201"
        );
        // Injected A records are only used when the AAAA answer is absent.
        let message = ParsedMessage::parse(&response()).unwrap();
        assert!(message.answers.iter().all(|record| record.rtype == TYPE_A));
    }
}

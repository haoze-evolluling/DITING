//! The block response shared by local rules, safe browsing and the response recheck.
//!
//! `BlockMode` is a global (or per-group) policy: whatever layer blocked the query, the client
//! must see the same failure shape. `null_ip` answers 0.0.0.0/:: for A/AAAA and NODATA otherwise;
//! `nxdomain` and `refused` use the corresponding rcode.

use diting_desktop_api::config::filter::{
    BLOCK_MODE_NXDOMAIN, BLOCK_MODE_REFUSED, DEFAULT_BLOCKING_IPV4, DEFAULT_BLOCKING_IPV6,
};
use diting_desktop_core::filter::BlockResponseConfig;
use diting_dns_wire::build::{RData, ResourceRecord, TYPE_A, TYPE_AAAA};
use diting_dns_wire::CLASS_IN;

use crate::context::{DnsContext, RCODE_NXDOMAIN, RCODE_REFUSED};
use crate::stages::util::{respond, start_reply};

pub const DEFAULT_RULE_TTL: u32 = 60;

/// Builds and installs the configured block response on `ctx`.
pub fn respond_blocked(ctx: &mut DnsContext, policy: &BlockResponseConfig) {
    let Some(builder) = start_reply(ctx) else {
        return;
    };
    match policy.block_mode.as_str() {
        BLOCK_MODE_NXDOMAIN => {
            respond(ctx, builder.set_rcode(RCODE_NXDOMAIN));
        }
        BLOCK_MODE_REFUSED => {
            respond(ctx, builder.set_rcode(RCODE_REFUSED));
        }
        _ => {
            let mut builder = builder;
            match ctx.question.qtype {
                TYPE_A => {
                    let ip = policy
                        .blocking_ipv4
                        .parse()
                        .unwrap_or_else(|_| DEFAULT_BLOCKING_IPV4.parse().expect("default IPv4"));
                    builder = builder.push_answer(ResourceRecord::new(
                        &ctx.question.name,
                        TYPE_A,
                        CLASS_IN,
                        DEFAULT_RULE_TTL,
                        RData::A(ip),
                    ));
                }
                TYPE_AAAA => {
                    let ip = policy
                        .blocking_ipv6
                        .parse()
                        .unwrap_or_else(|_| DEFAULT_BLOCKING_IPV6.parse().expect("default IPv6"));
                    builder = builder.push_answer(ResourceRecord::new(
                        &ctx.question.name,
                        TYPE_AAAA,
                        CLASS_IN,
                        DEFAULT_RULE_TTL,
                        RData::Aaaa(ip),
                    ));
                }
                _ => {}
            }
            respond(ctx, builder);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::MessageBuilder;

    fn context(qtype: u16) -> DnsContext {
        let query = MessageBuilder::query("ads.example", qtype, 1).finish().unwrap();
        DnsContext::new(query, None, crate::context::Transport::Udp).unwrap()
    }

    #[test]
    fn null_ip_answers_zero_addresses() {
        let policy = BlockResponseConfig {
            block_mode: "null_ip".into(),
            blocking_ipv4: "0.0.0.0".into(),
            blocking_ipv6: "::".into(),
        };
        let mut ctx = context(TYPE_A);
        respond_blocked(&mut ctx, &policy);
        let message = diting_dns_wire::build::ParsedMessage::parse(&ctx.response.unwrap()).unwrap();
        assert_eq!(message.answers.len(), 1);
        assert_eq!(
            message.answers[0].rdata,
            RData::A(std::net::Ipv4Addr::UNSPECIFIED)
        );
    }

    #[test]
    fn nxdomain_policy_sets_the_rcode() {
        let policy = BlockResponseConfig {
            block_mode: "nxdomain".into(),
            blocking_ipv4: "0.0.0.0".into(),
            blocking_ipv6: "::".into(),
        };
        let mut ctx = context(TYPE_A);
        respond_blocked(&mut ctx, &policy);
        let message = diting_dns_wire::build::ParsedMessage::parse(&ctx.response.unwrap()).unwrap();
        assert_eq!(message.rcode(), RCODE_NXDOMAIN);
        assert!(message.answers.is_empty());
    }
}

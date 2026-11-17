//! DNS rebinding protection.
//!
//! A public name resolving to a private/loopback/link-local address is the classic rebinding
//! attack: the browser resolves once to the attacker's server, then again to a LAN device. The
//! stage checks all answer sections (SVCB hints included), honours the allowlist (`localhost`,
//! `.lan`, ...), evicts the poisoned cache entry and replaces the answer with an empty NOERROR.

use std::net::IpAddr;
use std::sync::Arc;

use async_trait::async_trait;
use diting_dns_wire::build::ParsedMessage;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{attr_is_true, message_ips, normalized_name, respond, start_reply};
use crate::stages::ConfigHandle;

pub struct RebindStage {
    config: ConfigHandle,
    cache: Option<Arc<diting_desktop_core::cache::DesktopCache>>,
}

impl RebindStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self {
            config,
            cache: None,
        }
    }

    pub fn with_cache(mut self, cache: Arc<diting_desktop_core::cache::DesktopCache>) -> Self {
        self.cache = Some(cache);
        self
    }
}

#[async_trait]
impl Stage for RebindStage {
    fn name(&self) -> &'static str {
        "rebind"
    }

    async fn before(&self, _ctx: &mut DnsContext) -> StageResult {
        StageResult::Continue
    }

    async fn after(&self, ctx: &mut DnsContext) {
        let (enabled, allowed) = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            (config.rebind.enabled, config.rebind.allowed_domains.clone())
        };
        if !enabled || attr_is_true(ctx, "filter_blocked") {
            return;
        }
        let Some(response) = ctx.response.as_ref() else {
            return;
        };
        let Some(message) = ParsedMessage::parse(response) else {
            return;
        };
        let Some(blocked) = message_ips(&message)
            .into_iter()
            .find(|ip| is_blocked_ip(*ip))
        else {
            return;
        };
        let domain = normalized_name(&ctx.question.name);
        if is_domain_allowed(&domain, &allowed) {
            return;
        }
        // The cache may have stored this answer just before this postlude; evict it so the next
        // query does not get the poisoned record from memory.
        if let Some(cache) = &self.cache {
            if let Some(key) = cache.key_for(&ctx.request, &ctx.group) {
                cache.raw().remove_keyed(&key);
            }
        }
        if let Some(builder) = start_reply(ctx) {
            respond(ctx, builder);
        }
        ctx.set("rebinding_blocked", "true");
        ctx.set("filter_action", "block");
        ctx.set("filter_blocked", "true");
        ctx.set(
            "filter_reason",
            format!("DNS Rebinding 攻击防护: 外部域名解析为非受信内网 IP ({blocked})"),
        );
    }
}

/// RFC 1918, RFC 4193 ULA, RFC 3927 link-local, loopback, unspecified, and NAT64-embedded private.
pub fn is_blocked_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            ip.is_private() || ip.is_loopback() || ip.is_link_local() || ip.is_unspecified()
        }
        IpAddr::V6(ip) => {
            if ip.is_loopback() || ip.is_unspecified() || ip.is_unicast_link_local() {
                return true;
            }
            let octets = ip.octets();
            if is_unique_local(&octets) {
                return true;
            }
            // RFC 6052 64:ff9b::/96 embeds an IPv4 address that may itself be private.
            const NAT64: [u8; 12] = [0x00, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0];
            if octets[..12] == NAT64 {
                return is_blocked_ip(IpAddr::V4(std::net::Ipv4Addr::new(
                    octets[12], octets[13], octets[14], octets[15],
                )));
            }
            false
        }
    }
}

fn is_unique_local(octets: &[u8; 16]) -> bool {
    octets[0] & 0xfe == 0xfc
}

pub fn is_domain_allowed(domain: &str, allowed: &[String]) -> bool {
    let domain = normalized_name(domain);
    allowed.iter().any(|entry| {
        let entry = entry
            .trim()
            .trim_start_matches('*')
            .trim_matches('.')
            .to_ascii_lowercase();
        !entry.is_empty() && (domain == entry || domain.ends_with(&format!(".{entry}")))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_and_nat64_addresses_are_blocked() {
        assert!(is_blocked_ip("192.168.1.1".parse().unwrap()));
        assert!(is_blocked_ip("127.0.0.1".parse().unwrap()));
        assert!(is_blocked_ip("fe80::1".parse().unwrap()));
        assert!(is_blocked_ip("fd00::1".parse().unwrap()));
        assert!(is_blocked_ip("64:ff9b::c0a8:101".parse().unwrap()));
        assert!(!is_blocked_ip("8.8.8.8".parse().unwrap()));
        assert!(!is_blocked_ip("2001:4860:4860::8888".parse().unwrap()));
    }

    #[test]
    fn allowlist_matches_suffixes() {
        let allowed = vec![".lan".to_string(), "localhost".to_string()];
        assert!(is_domain_allowed("nas.lan", &allowed));
        assert!(is_domain_allowed("localhost", &allowed));
        assert!(!is_domain_allowed("example.com", &allowed));
    }

    struct Embedded;

    impl Embedded {
        fn build(query: &[u8]) -> Vec<u8> {
            use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord};
            MessageBuilder::reply_to(query)
                .unwrap()
                .push_answer(ResourceRecord::new(
                    "evil.example",
                    1,
                    1,
                    60,
                    RData::A(std::net::Ipv4Addr::new(192, 168, 1, 1)),
                ))
                .finish()
                .unwrap()
        }
    }

    #[tokio::test]
    async fn poisoning_answer_is_replaced() {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        let stage = RebindStage::new(config);
        let query = diting_dns_wire::build::MessageBuilder::query("evil.example", 1, 1)
            .finish()
            .unwrap();
        let mut ctx = DnsContext::new(query, None, crate::context::Transport::Udp).unwrap();
        ctx.response = Some(Embedded::build(&ctx.request));
        stage.after(&mut ctx).await;
        let message = ParsedMessage::parse(ctx.response.as_ref().unwrap()).unwrap();
        assert!(message.answers.is_empty());
        assert!(attr_is_true(&ctx, "rebinding_blocked"));
    }
}

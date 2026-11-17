//! RFC 6303 / RFC 7793 private reverse zones.
//!
//! Reverse lookups for RFC 1918, CGNAT, link-local, ULA and loopback space must never leave the
//! machine. When hosts/rewrite produced nothing, this stage answers NXDOMAIN with a zone-apex SOA
//! so negative caching aggregates per zone rather than per address.

use async_trait::async_trait;
use diting_dns_wire::build::{RData, ResourceRecord, TYPE_PTR};
use diting_dns_wire::{CLASS_IN, TYPE_PTR as TYPE_PTR_QUERY};

use crate::context::{DnsContext, RCODE_NXDOMAIN};
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{negative_soa, normalized_name, respond, start_reply};
use crate::stages::ConfigHandle;

const PRIVATE_REVERSE_SUFFIXES: &[&str] = &[
    "10.in-addr.arpa",
    "168.192.in-addr.arpa",
    "16.172.in-addr.arpa",
    "17.172.in-addr.arpa",
    "18.172.in-addr.arpa",
    "19.172.in-addr.arpa",
    "20.172.in-addr.arpa",
    "21.172.in-addr.arpa",
    "22.172.in-addr.arpa",
    "23.172.in-addr.arpa",
    "24.172.in-addr.arpa",
    "25.172.in-addr.arpa",
    "26.172.in-addr.arpa",
    "27.172.in-addr.arpa",
    "28.172.in-addr.arpa",
    "29.172.in-addr.arpa",
    "30.172.in-addr.arpa",
    "31.172.in-addr.arpa",
    "64.100.in-addr.arpa",
    "65.100.in-addr.arpa",
    "66.100.in-addr.arpa",
    "67.100.in-addr.arpa",
    "68.100.in-addr.arpa",
    "69.100.in-addr.arpa",
    "70.100.in-addr.arpa",
    "71.100.in-addr.arpa",
    "72.100.in-addr.arpa",
    "73.100.in-addr.arpa",
    "74.100.in-addr.arpa",
    "75.100.in-addr.arpa",
    "76.100.in-addr.arpa",
    "77.100.in-addr.arpa",
    "78.100.in-addr.arpa",
    "79.100.in-addr.arpa",
    "80.100.in-addr.arpa",
    "81.100.in-addr.arpa",
    "82.100.in-addr.arpa",
    "83.100.in-addr.arpa",
    "84.100.in-addr.arpa",
    "85.100.in-addr.arpa",
    "86.100.in-addr.arpa",
    "87.100.in-addr.arpa",
    "88.100.in-addr.arpa",
    "89.100.in-addr.arpa",
    "90.100.in-addr.arpa",
    "91.100.in-addr.arpa",
    "92.100.in-addr.arpa",
    "93.100.in-addr.arpa",
    "94.100.in-addr.arpa",
    "95.100.in-addr.arpa",
    "96.100.in-addr.arpa",
    "97.100.in-addr.arpa",
    "98.100.in-addr.arpa",
    "99.100.in-addr.arpa",
    "100.100.in-addr.arpa",
    "101.100.in-addr.arpa",
    "102.100.in-addr.arpa",
    "103.100.in-addr.arpa",
    "104.100.in-addr.arpa",
    "105.100.in-addr.arpa",
    "106.100.in-addr.arpa",
    "107.100.in-addr.arpa",
    "108.100.in-addr.arpa",
    "109.100.in-addr.arpa",
    "110.100.in-addr.arpa",
    "111.100.in-addr.arpa",
    "112.100.in-addr.arpa",
    "113.100.in-addr.arpa",
    "114.100.in-addr.arpa",
    "115.100.in-addr.arpa",
    "116.100.in-addr.arpa",
    "117.100.in-addr.arpa",
    "118.100.in-addr.arpa",
    "119.100.in-addr.arpa",
    "120.100.in-addr.arpa",
    "121.100.in-addr.arpa",
    "122.100.in-addr.arpa",
    "123.100.in-addr.arpa",
    "124.100.in-addr.arpa",
    "125.100.in-addr.arpa",
    "126.100.in-addr.arpa",
    "127.100.in-addr.arpa",
    "254.169.in-addr.arpa",
    "127.in-addr.arpa",
    "0.in-addr.arpa",
    "255.255.255.255.in-addr.arpa",
    "2.0.192.in-addr.arpa",
    "100.51.198.in-addr.arpa",
    "113.0.203.in-addr.arpa",
    "c.f.ip6.arpa",
    "d.f.ip6.arpa",
    "8.e.f.ip6.arpa",
    "9.e.f.ip6.arpa",
    "a.e.f.ip6.arpa",
    "b.e.f.ip6.arpa",
    "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa",
    "0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa",
    "8.b.d.0.1.0.0.2.ip6.arpa",
];

pub fn is_private_reverse_zone(domain: &str) -> bool {
    let clean = normalized_name(domain);
    PRIVATE_REVERSE_SUFFIXES
        .iter()
        .any(|suffix| clean == *suffix || clean.ends_with(&format!(".{suffix}")))
}

/// The most specific matching suffix, dot-terminated. `None` when not a private zone.
pub fn private_reverse_zone_apex(domain: &str) -> Option<String> {
    let clean = normalized_name(domain);
    let mut best: Option<&str> = None;
    for suffix in PRIVATE_REVERSE_SUFFIXES {
        if (clean == *suffix || clean.ends_with(&format!(".{suffix}")))
            && best
                .map(|current| suffix.len() > current.len())
                .unwrap_or(true)
        {
            best = Some(suffix);
        }
    }
    best.map(|suffix| format!("{suffix}."))
}

/// Parses `1.1.168.192.in-addr.arpa` or a 32-nibble `ip6.arpa` name.
pub fn parse_ptr_ip(name: &str) -> Option<std::net::IpAddr> {
    let clean = normalized_name(name);
    if let Some(rest) = clean.strip_suffix(".in-addr.arpa") {
        let labels: Vec<&str> = rest.split('.').collect();
        if labels.len() != 4 {
            return None;
        }
        let mut octets = [0u8; 4];
        for (index, label) in labels.iter().enumerate() {
            octets[3 - index] = label.parse::<u8>().ok()?;
        }
        return Some(std::net::IpAddr::V4(std::net::Ipv4Addr::from(octets)));
    }
    if let Some(rest) = clean.strip_suffix(".ip6.arpa") {
        let nibbles: Vec<&str> = rest.split('.').collect();
        if nibbles.len() != 32 {
            return None;
        }
        let mut octets = [0u8; 16];
        for (index, octet) in octets.iter_mut().enumerate() {
            let high = u8::from_str_radix(nibbles[31 - index * 2], 16).ok()?;
            let low = u8::from_str_radix(nibbles[31 - index * 2 - 1], 16).ok()?;
            *octet = (high << 4) | low;
        }
        return Some(std::net::IpAddr::V6(std::net::Ipv6Addr::from(octets)));
    }
    None
}

pub struct PrivatePtrStage {
    config: ConfigHandle,
}

impl PrivatePtrStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for PrivatePtrStage {
    fn name(&self) -> &'static str {
        "private_ptr"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let enabled = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            config.dns.block_private_ptr
        };
        if !enabled || ctx.question.qtype != TYPE_PTR_QUERY {
            return StageResult::Continue;
        }
        if !is_private_reverse_zone(&ctx.question.name) {
            return StageResult::Continue;
        }
        let Some(builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        let zone = private_reverse_zone_apex(&ctx.question.name)
            .unwrap_or_else(|| crate::stages::util::normalize_trailing_dot(&ctx.question.name));
        let builder = builder
            .set_rcode(RCODE_NXDOMAIN)
            .push_authority(negative_soa(&zone, 300));
        respond(ctx, builder);
        ctx.set("source", "locally_served_zone");
        ctx.set("private_ptr_blocked", "true");
        StageResult::Stop
    }
}

/// Builds a PTR answer when the client resolver knows the address (used by the client stage).
pub fn ptr_answer(ctx: &DnsContext, host: &str, ttl: u32) -> Option<Vec<u8>> {
    let target = crate::stages::util::normalize_trailing_dot(host);
    start_reply(ctx)?
        .push_answer(ResourceRecord::new(
            &ctx.question.name,
            TYPE_PTR,
            CLASS_IN,
            ttl,
            RData::Ptr(target),
        ))
        .finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ipv4_and_ipv6_reverse_names_parse() {
        assert_eq!(
            parse_ptr_ip("1.1.168.192.in-addr.arpa.")
                .unwrap()
                .to_string(),
            "192.168.1.1"
        );
        assert_eq!(
            parse_ptr_ip(
                "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa"
            )
            .unwrap()
            .to_string(),
            "::1"
        );
    }

    #[test]
    fn apex_uses_the_longest_match() {
        assert_eq!(
            private_reverse_zone_apex("5.1.168.192.in-addr.arpa.").as_deref(),
            Some("168.192.in-addr.arpa.")
        );
        assert!(is_private_reverse_zone("c.f.ip6.arpa"));
        assert!(!is_private_reverse_zone("example.com"));
    }
}

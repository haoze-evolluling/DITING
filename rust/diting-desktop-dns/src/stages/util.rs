use std::borrow::Cow;
use std::net::IpAddr;

use diting_dns_wire::build::{
    MessageBuilder, ParsedMessage, RData, ResourceRecord, SvcParam, SVCB_KEY_IPV4HINT,
    SVCB_KEY_IPV6HINT, TYPE_HTTPS, TYPE_SOA, TYPE_SVCB,
};
use diting_dns_wire::CLASS_IN;

use crate::context::DnsContext;

pub fn start_reply(ctx: &DnsContext) -> Option<MessageBuilder> {
    MessageBuilder::reply_to(&ctx.request).map(|builder| {
        builder
            .set_authoritative(true)
            .set_recursion_available(true)
    })
}

pub fn respond(ctx: &mut DnsContext, builder: MessageBuilder) {
    ctx.response = builder.finish();
}

pub fn negative_soa(zone: &str, ttl: u32) -> ResourceRecord {
    ResourceRecord::new(
        normalize_trailing_dot(zone),
        TYPE_SOA,
        CLASS_IN,
        ttl,
        RData::Soa {
            mname: "localhost.".to_string(),
            rname: "nobody.invalid.".to_string(),
            serial: 1,
            refresh: 10_000,
            retry: 2_400,
            expire: 604_800,
            minimum: 300,
        },
    )
}

pub fn normalize_trailing_dot(name: &str) -> String {
    if name.ends_with('.') {
        name.to_string()
    } else {
        format!("{name}.")
    }
}

pub fn normalized_name(name: &str) -> Cow<'_, str> {
    let trimmed = name.trim().trim_end_matches('.');
    if trimmed.bytes().any(|byte| byte.is_ascii_uppercase()) {
        Cow::Owned(trimmed.to_ascii_lowercase())
    } else {
        Cow::Borrowed(trimmed)
    }
}

#[inline]
pub fn domain_or_suffix(name: &str, suffix: &str) -> bool {
    name == suffix
        || (name.len() > suffix.len()
            && name.ends_with(suffix)
            && name.as_bytes()[name.len() - suffix.len() - 1] == b'.')
}

pub fn attr_is_true(ctx: &DnsContext, key: &str) -> bool {
    ctx.get(key) == Some("true")
}


pub fn message_ips(message: &ParsedMessage) -> Vec<IpAddr> {
    let mut result = Vec::new();
    for record in message
        .answers
        .iter()
        .chain(message.authorities.iter())
        .chain(message.additionals.iter())
    {
        collect_record_ips(record, &mut result);
    }
    result
}


#[allow(clippy::chunks_exact_to_as_chunks)]
fn collect_record_ips(record: &ResourceRecord, result: &mut Vec<IpAddr>) {
    match &record.rdata {
        RData::A(ip) => result.push(IpAddr::V4(*ip)),
        RData::Aaaa(ip) => result.push(IpAddr::V6(*ip)),
        RData::Https(svcb) | RData::Svcb(svcb) => {
            for param in &svcb.params {
                match param.key {
                    SVCB_KEY_IPV4HINT => {
                        for chunk in param.value.chunks_exact(4) {
                            result.push(IpAddr::V4(std::net::Ipv4Addr::new(
                                chunk[0], chunk[1], chunk[2], chunk[3],
                            )));
                        }
                    }
                    SVCB_KEY_IPV6HINT => {
                        for chunk in param.value.chunks_exact(16) {
                            let mut octets = [0u8; 16];
                            octets.copy_from_slice(chunk);
                            result.push(IpAddr::V6(std::net::Ipv6Addr::from(octets)));
                        }
                    }
                    _ => {}
                }
            }
        }
        _ => {}
    }
}

pub fn strip_ech(message: &mut ParsedMessage) -> bool {
    let mut changed = false;
    for record in message
        .answers
        .iter_mut()
        .chain(message.authorities.iter_mut())
        .chain(message.additionals.iter_mut())
    {
        if record.rtype != TYPE_HTTPS && record.rtype != TYPE_SVCB {
            continue;
        }
        match &mut record.rdata {
            RData::Https(svcb) | RData::Svcb(svcb) => {
                let before = svcb.params.len();
                svcb.params.retain(|param| param.key != 5);
                changed |= svcb.params.len() != before;
            }
            _ => {}
        }
    }
    changed
}

pub fn strip_ipv6_hints(message: &mut ParsedMessage) -> bool {
    let mut changed = false;
    for record in message
        .answers
        .iter_mut()
        .chain(message.authorities.iter_mut())
        .chain(message.additionals.iter_mut())
    {
        match &mut record.rdata {
            RData::Https(svcb) | RData::Svcb(svcb) => {
                let before = svcb.params.len();
                svcb.params.retain(|param| param.key != SVCB_KEY_IPV6HINT);
                changed |= svcb.params.len() != before;
            }
            _ => {}
        }
    }
    changed
}

pub fn svc_param(key: u16, value: Vec<u8>) -> SvcParam {
    SvcParam { key, value }
}

pub fn add_ede(message: &mut ParsedMessage, code: u16, text: &str) {
    message.push_opt_option(diting_dns_wire::build::EdnsOption::Ede(
        diting_dns_wire::build::EdeOption::new(code, text),
    ));
}


#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord};
    use diting_dns_wire::parse_question;

    fn response_with_https() -> Vec<u8> {
        let query = MessageBuilder::query("example.com", 1, 1).finish().unwrap();
        let svcb = diting_dns_wire::build::SvcbRData::new(1, ".")
            .push(svc_param(5, vec![1, 2, 3]))
            .push(SvcParam::ipv6hint(&["2001:db8::1".parse().unwrap()]));
        MessageBuilder::reply_to(&query)
            .unwrap()
            .push_answer(ResourceRecord::new(
                "example.com",
                TYPE_HTTPS,
                CLASS_IN,
                60,
                RData::Https(svcb),
            ))
            .finish()
            .unwrap()
    }

    #[test]
    fn strips_ech_and_ipv6_hints() {
        let wire = response_with_https();
        let mut message = ParsedMessage::parse(&wire).unwrap();
        assert!(strip_ech(&mut message));
        assert!(strip_ipv6_hints(&mut message));
        let rebuilt = message.to_wire().unwrap();
        let parsed = ParsedMessage::parse(&rebuilt).unwrap();
        let RData::Https(svcb) = &parsed.answers[0].rdata else {
            panic!("expected HTTPS");
        };
        assert!(svcb.params.is_empty());
        assert!(!strip_ech(&mut message));
    }

    #[test]
    fn negative_soa_uses_zone_apex() {
        let record = negative_soa("168.192.in-addr.arpa", 300);
        assert_eq!(record.name, "168.192.in-addr.arpa.");
        assert_eq!(record.ttl, 300);
    }

    #[test]
    fn question_helper_keeps_the_name() {
        let query = MessageBuilder::query("example.com", 1, 1).finish().unwrap();
        let (question, _) = parse_question(&query, 12, false).unwrap();
        assert_eq!(normalized_name(&question.name), "example.com");
    }
}

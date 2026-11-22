use diting_desktop_core::filter::{ResponseRecord, ResponseRecordKind};
use diting_dns_wire::build::{ParsedMessage, RData, ResourceRecord, SvcParam, SvcbRData};
use diting_rewrite_core::record::{Record as KernelRecord, SvcParam as KernelSvcParam};
use diting_rewrite_core::ParsedRecord;

pub fn to_wire_record(parsed: &ParsedRecord) -> Option<ResourceRecord> {
    Some(ResourceRecord::new(
        parsed.owner.clone(),
        parsed.record.rrtype(),
        1,
        parsed.ttl,
        to_wire_rdata(&parsed.record),
    ))
}

pub fn to_wire_rdata(record: &KernelRecord) -> RData {
    match record {
        KernelRecord::A(bytes) => RData::A(std::net::Ipv4Addr::from(*bytes)),
        KernelRecord::Aaaa(bytes) => RData::Aaaa(std::net::Ipv6Addr::from(*bytes)),
        KernelRecord::Cname(name) => RData::Cname(name.clone()),
        KernelRecord::Ns(name) => RData::Ns(name.clone()),
        KernelRecord::Ptr(name) => RData::Ptr(name.clone()),
        KernelRecord::Txt(values) => RData::Txt(
            values
                .iter()
                .map(|value| value.as_bytes().to_vec())
                .collect(),
        ),
        KernelRecord::Mx {
            preference,
            exchange,
        } => RData::Mx {
            preference: *preference,
            exchange: exchange.clone(),
        },
        KernelRecord::Srv {
            priority,
            weight,
            port,
            target,
        } => RData::Srv {
            priority: *priority,
            weight: *weight,
            port: *port,
            target: target.clone(),
        },
        KernelRecord::Svcb {
            https,
            priority,
            target,
            params,
        } => {
            let svcb = SvcbRData {
                priority: *priority,
                target: target.clone(),
                params: params.iter().map(to_wire_svc_param).collect(),
            };
            if *https {
                RData::Https(svcb)
            } else {
                RData::Svcb(svcb)
            }
        }
    }
}

fn to_wire_svc_param(param: &KernelSvcParam) -> SvcParam {
    let key = param.key();
    let value = match param {
        KernelSvcParam::Mandatory(keys) => keys.iter().flat_map(|key| key.to_be_bytes()).collect(),
        KernelSvcParam::Alpn(protocols) => {
            let mut value = Vec::new();
            for protocol in protocols {
                value.push(protocol.len() as u8);
                value.extend_from_slice(protocol.as_bytes());
            }
            value
        }
        KernelSvcParam::NoDefaultAlpn => Vec::new(),
        KernelSvcParam::Port(port) => port.to_be_bytes().to_vec(),
        KernelSvcParam::Ipv4Hint(addresses) => {
            addresses.iter().flat_map(|address| *address).collect()
        }
        KernelSvcParam::Ech(data) => data.clone(),
        KernelSvcParam::Ipv6Hint(addresses) => {
            addresses.iter().flat_map(|address| *address).collect()
        }
        KernelSvcParam::DoHPath(path) => path.as_bytes().to_vec(),
    };
    SvcParam { key, value }
}

pub fn response_records(message: &ParsedMessage) -> Vec<ResponseRecord> {
    message
        .answers
        .iter()
        .map(|record| {
            let kind = match &record.rdata {
                RData::A(_) => ResponseRecordKind::A,
                RData::Aaaa(_) => ResponseRecordKind::Aaaa,
                RData::Cname(_) => ResponseRecordKind::Cname,
                RData::Https(_) => ResponseRecordKind::Https,
                RData::Svcb(_) => ResponseRecordKind::Svcb,
                _ => ResponseRecordKind::Other,
            };
            let target = match &record.rdata {
                RData::Cname(target) => Some(target.clone()),
                RData::Https(svcb) | RData::Svcb(svcb) => Some(svcb.target.clone()),
                _ => None,
            };
            ResponseRecord {
                owner: record.name.clone(),
                kind,
                target,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{
        MessageBuilder, RData as WireRData, ResourceRecord as WireRecord,
    };

    #[test]
    fn response_records_preserve_alias_targets() {
        let query = MessageBuilder::query("a.example", 1, 1).finish().unwrap();
        let response = MessageBuilder::reply_to(&query)
            .unwrap()
            .push_answer(WireRecord::new(
                "a.example",
                5,
                1,
                60,
                WireRData::Cname("b.example".into()),
            ))
            .push_answer(WireRecord::new(
                "b.example",
                1,
                1,
                60,
                WireRData::A("192.0.2.1".parse().unwrap()),
            ))
            .finish()
            .unwrap();
        let records = response_records(&ParsedMessage::parse(&response).unwrap());
        assert_eq!(records.len(), 2);
        assert_eq!(records[0].kind, ResponseRecordKind::Cname);
        assert_eq!(records[0].target.as_deref(), Some("b.example."));
        assert_eq!(records[1].kind, ResponseRecordKind::A);
    }

    #[test]
    fn svcb_alpn_round_trips_through_the_wire_builder() {
        let record = KernelRecord::Svcb {
            https: true,
            priority: 1,
            target: ".".into(),
            params: vec![
                KernelSvcParam::Alpn(vec!["h2".into(), "http/1.1".into()]),
                KernelSvcParam::Port(8443),
            ],
        };
        let wire = to_wire_rdata(&record);
        let WireRData::Https(svcb) = wire else {
            panic!("expected HTTPS");
        };
        assert_eq!(svcb.params.len(), 2);
        assert_eq!(
            svcb.params[0].value,
            vec![2, b'h', b'2', 8, b'h', b't', b't', b'p', b'/', b'1', b'.', b'1']
        );
        assert_eq!(svcb.params[1].value, 8443u16.to_be_bytes());
    }
}

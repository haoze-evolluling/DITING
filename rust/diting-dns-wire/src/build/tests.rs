//! Builder cases: round-trips through the existing readers, every rdata encoder and EDNS.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use super::*;
use crate::{
    parse_answer_records, parse_header, parse_question, parse_response, ChainKind,
};

fn name_wire(name: &str) -> Vec<u8> {
    let mut out = Vec::new();
    assert!(crate::pack_name(name, &mut out), "{name} packs");
    out
}

fn record(name: &str, rtype: u16, rdata: RData) -> ResourceRecord {
    ResourceRecord::new(name, rtype, CLASS_IN, 60, rdata)
}

/// Encodes rdata with no prior message state, so names come out uncompressed.
fn encode_rdata(rdata: &RData) -> Vec<u8> {
    let mut out = Vec::new();
    assert!(rdata.encode(&mut NameWriter::new(), &mut out));
    out
}

fn query() -> Vec<u8> {
    MessageBuilder::query("www.example.com.", TYPE_A, CLASS_IN)
        .set_id(0x1a2b)
        .finish()
        .expect("query")
}

#[test]
fn query_and_reply_round_trip() {
    let query = query();
    let header = parse_header(&query).expect("header");
    assert_eq!(header.id, 0x1a2b);
    assert!(!header.is_response());
    assert_eq!(header.flags & 0x0100, 0x0100);
    assert_eq!(header.question_count, 1);
    assert_eq!(header.answer_count, 0);

    let (question, end) = parse_question(&query, 12, true).expect("question");
    assert_eq!(question.name, "www.example.com.");
    assert_eq!(question.qtype, TYPE_A);
    assert_eq!(question.qclass, CLASS_IN);
    assert_eq!(end, query.len());

    let reply = MessageBuilder::reply_to(&query)
        .expect("reply")
        .set_authoritative(true)
        .set_recursion_available(true)
        .push_answer(record(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(1, 2, 3, 4)),
        ))
        .finish()
        .expect("reply wire");

    let header = parse_header(&reply).expect("header");
    assert_eq!(header.id, 0x1a2b);
    assert!(header.is_response());
    assert_eq!(header.flags & 0x0100, 0x0100, "RD copied");
    assert_eq!(header.flags & 0x0400, 0x0400, "AA set");
    assert_eq!(header.flags & 0x0080, 0x0080, "RA set");
    assert_eq!(header.question_count, 1);
    assert_eq!(header.answer_count, 1);
    assert_eq!(parse_question(&reply, 12, true).unwrap().0, question);

    let meta = parse_response(&reply).expect("response");
    assert_eq!(meta.ips, vec!["1.2.3.4".to_string()]);
}

#[test]
fn rcode_and_truncated_flags_are_encoded() {
    let wire = MessageBuilder::reply_to(&query())
        .expect("reply")
        .set_rcode(3)
        .set_truncated(true)
        .finish()
        .expect("wire");
    let header = parse_header(&wire).unwrap();
    assert_eq!(header.flags & 0x000f, 3);
    assert_eq!(header.flags & 0x0200, 0x0200);
}

#[test]
fn reply_to_copies_cd_and_rejects_non_queries() {
    let query = MessageBuilder::query("example.test.", TYPE_A, CLASS_IN)
        .set_checking_disabled(true)
        .finish()
        .unwrap();
    let reply = MessageBuilder::reply_to(&query).expect("reply").finish().unwrap();
    let header = parse_header(&reply).unwrap();
    assert_eq!(header.flags & 0x0010, 0x0010, "CD copied");
    assert!(header.is_response());

    let mut marked_response = query.clone();
    marked_response[2] |= 0x80;
    assert!(MessageBuilder::reply_to(&marked_response).is_none());

    let mut no_question = query.clone();
    no_question[4..6].copy_from_slice(&0u16.to_be_bytes());
    assert!(MessageBuilder::reply_to(&no_question).is_none());

    let mut two_questions = query.clone();
    two_questions[4..6].copy_from_slice(&2u16.to_be_bytes());
    assert!(MessageBuilder::reply_to(&two_questions).is_none());

    assert!(MessageBuilder::reply_to(&[]).is_none());
}

#[test]
fn rdata_encoders_emit_expected_wire_bytes() {
    assert_eq!(
        encode_rdata(&RData::A(Ipv4Addr::new(192, 0, 2, 1))),
        vec![192, 0, 2, 1]
    );
    assert_eq!(
        encode_rdata(&RData::Aaaa(Ipv6Addr::LOCALHOST)),
        vec![0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    );
    assert_eq!(
        encode_rdata(&RData::Cname("target.example.".to_string())),
        name_wire("target.example.")
    );
    assert_eq!(
        encode_rdata(&RData::Ptr("ptr.example.".to_string())),
        name_wire("ptr.example.")
    );
    assert_eq!(
        encode_rdata(&RData::Ns("ns.example.".to_string())),
        name_wire("ns.example.")
    );

    let mut soa = name_wire("ns1.test.");
    soa.extend(name_wire("hostmaster.invalid."));
    for value in [1u32, 2, 3, 4, 5] {
        soa.extend(value.to_be_bytes());
    }
    assert_eq!(
        encode_rdata(&RData::Soa {
            mname: "ns1.test.".to_string(),
            rname: "hostmaster.invalid.".to_string(),
            serial: 1,
            refresh: 2,
            retry: 3,
            expire: 4,
            minimum: 5,
        }),
        soa
    );

    let mut mx = 10u16.to_be_bytes().to_vec();
    mx.extend(name_wire("mail.example."));
    assert_eq!(
        encode_rdata(&RData::Mx {
            preference: 10,
            exchange: "mail.example.".to_string(),
        }),
        mx
    );

    assert_eq!(
        encode_rdata(&RData::txt(["hello", "world"])),
        b"\x05hello\x05world".to_vec()
    );

    let mut srv = Vec::new();
    srv.extend(1u16.to_be_bytes());
    srv.extend(2u16.to_be_bytes());
    srv.extend(443u16.to_be_bytes());
    srv.extend(name_wire("target.example."));
    assert_eq!(
        encode_rdata(&RData::Srv {
            priority: 1,
            weight: 2,
            port: 443,
            target: "target.example.".to_string(),
        }),
        srv
    );

    assert_eq!(
        encode_rdata(&RData::Hinfo {
            cpu: "x86".to_string(),
            os: "linux".to_string(),
        }),
        b"\x03x86\x05linux".to_vec()
    );

    let mut caa = vec![0u8, 5];
    caa.extend_from_slice(b"issue");
    caa.extend_from_slice(b"letsencrypt.org");
    assert_eq!(
        encode_rdata(&RData::Caa {
            flags: 0,
            tag: "issue".to_string(),
            value: b"letsencrypt.org".to_vec(),
        }),
        caa
    );

    let mut naptr = Vec::new();
    naptr.extend(100u16.to_be_bytes());
    naptr.extend(10u16.to_be_bytes());
    naptr.extend_from_slice(b"\x01S");
    naptr.extend_from_slice(b"\x07SIP+D2U");
    naptr.push(0);
    naptr.extend(name_wire("sip.example."));
    assert_eq!(
        encode_rdata(&RData::Naptr {
            order: 100,
            preference: 10,
            flags: "S".to_string(),
            services: "SIP+D2U".to_string(),
            regexp: String::new(),
            replacement: "sip.example.".to_string(),
        }),
        naptr
    );

    assert_eq!(encode_rdata(&RData::Raw(vec![0xde, 0xad])), vec![0xde, 0xad]);
}

#[test]
fn svc_param_helpers_and_svcb_encoding() {
    assert_eq!(
        SvcParam::alpn(&["h2", "h3"]).value,
        b"\x02h2\x02h3".to_vec()
    );
    assert_eq!(SvcParam::port(443).value, vec![0x01, 0xbb]);
    assert_eq!(SvcParam::dohpath("/dns-query").value, b"/dns-query".to_vec());
    assert_eq!(
        SvcParam::ipv4hint(&[Ipv4Addr::new(1, 2, 3, 4)]).value,
        vec![1, 2, 3, 4]
    );
    assert_eq!(
        SvcParam::ipv6hint(&[Ipv6Addr::LOCALHOST]).value,
        vec![0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    );
    assert!(SvcParam::no_default_alpn().value.is_empty());

    // Parameters are written in ascending key order, whatever order they were pushed in.
    let data = SvcbRData::new(1, "svc.example.")
        .push(SvcParam::port(443))
        .push(SvcParam::alpn(&["h2"]));
    let mut expected = vec![0u8, 1];
    expected.extend(name_wire("svc.example."));
    expected.extend_from_slice(b"\x00\x01\x00\x03\x02h2");
    expected.extend_from_slice(b"\x00\x03\x00\x02\x01\xbb");
    assert_eq!(encode_rdata(&RData::Svcb(data.clone())), expected);
    assert_eq!(encode_rdata(&RData::Https(data)), expected);

    // Duplicate keys are invalid and make the encoder refuse the record.
    let duplicate = SvcbRData::new(1, ".")
        .push(SvcParam::port(1))
        .push(SvcParam::port(2));
    let mut out = Vec::new();
    assert!(!RData::Svcb(duplicate).encode(&mut NameWriter::new(), &mut out));
}

#[test]
fn synthesized_response_parses_with_existing_readers() {
    let query = query();
    let reply = MessageBuilder::reply_to(&query)
        .expect("reply")
        .push_answer(record(
            "www.example.com.",
            TYPE_CNAME,
            RData::Cname("edge.example.net.".to_string()),
        ))
        .push_answer(record(
            "edge.example.net.",
            TYPE_A,
            RData::A(Ipv4Addr::new(203, 0, 113, 7)),
        ))
        .push_answer(record(
            "edge.example.net.",
            TYPE_HTTPS,
            RData::Https(
                SvcbRData::new(1, "alt.example.net.").push(SvcParam::alpn(&["h2"])),
            ),
        ))
        .finish()
        .expect("wire");

    let meta = parse_response(&reply).expect("response");
    assert_eq!(meta.ips, vec!["203.0.113.7".to_string()]);
    let chain: Vec<(&str, ChainKind)> = meta
        .chain_targets
        .iter()
        .map(|target| (target.domain.as_str(), target.kind))
        .collect();
    assert_eq!(
        chain,
        vec![
            ("edge.example.net", ChainKind::Cname),
            ("alt.example.net", ChainKind::Svcb),
        ]
    );

    let records = parse_answer_records(&reply).expect("records");
    assert_eq!(records.len(), 3);
    assert_eq!(records[0].name, "www.example.com.");
    assert_eq!(records[0].rrtype, TYPE_CNAME);
    assert_eq!(records[1].rdata, vec![203, 0, 113, 7]);
    assert_eq!(records[2].name, "edge.example.net.");
    assert_eq!(records[2].rrtype, TYPE_HTTPS);
}

#[test]
fn repeated_owner_names_use_compression_pointers() {
    let query = query();
    let reply = MessageBuilder::reply_to(&query)
        .expect("reply")
        .push_answer(record(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(1, 1, 1, 1)),
        ))
        .push_answer(record(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(2, 2, 2, 2)),
        ))
        .finish()
        .expect("wire");

    let records = parse_answer_records(&reply).expect("records");
    assert_eq!(records.len(), 2);
    assert_eq!(records[0].name, "www.example.com.");
    assert_eq!(records[1].name, "www.example.com.");
    let pointers = reply
        .windows(2)
        .filter(|pair| pair[0] == 0xc0 && pair[1] == 0x0c)
        .count();
    assert_eq!(pointers, 2, "both answer owner names point at the question");
    assert_eq!(
        parse_response(&reply).unwrap().ips,
        vec!["1.1.1.1".to_string(), "2.2.2.2".to_string()]
    );
}

#[test]
fn edns_options_round_trip_and_opt_is_last() {
    let opt = OptBuilder {
        ext_rcode: 1,
        z: 0x0123,
        do_bit: true,
        ..OptBuilder::new(1400)
    }
    .push_option(EdnsOption::Ecs(EcsOption::from_ip(
        IpAddr::V4(Ipv4Addr::new(192, 0, 2, 1)),
        24,
        0,
    )))
    .push_option(EdnsOption::Ede(EdeOption::new(15, "blocked by policy")))
    .push_option(EdnsOption::Padding(vec![0; 7]))
    .push_option(EdnsOption::Nsid(b"server-1".to_vec()))
    .push_option(EdnsOption::Cookie(vec![7; 16]))
    .push_option(EdnsOption::Unknown {
        code: 65001,
        data: vec![0xaa, 0xbb],
    });

    let wire = MessageBuilder::reply_to(&query())
        .expect("reply")
        .with_opt(opt.clone())
        .finish()
        .expect("wire");

    let header = parse_header(&wire).unwrap();
    assert_eq!(header.additional_count, 1);

    let info = parse_opt(&wire).expect("OPT");
    assert_eq!(info.udp_size, 1400);
    assert_eq!(info.ext_rcode, 1);
    assert_eq!(info.version, 0);
    assert!(info.do_bit);
    assert_eq!(info.z, 0x0123);
    assert_eq!(info.options, opt.options);

    // The last thing on the wire is the OPT TLV stream: an 11-byte empty OPT would end at the
    // root/type/class/ttl/rdlen; here the unknown option is last.
    assert!(wire.ends_with(&[0xfd, 0xe9, 0x00, 0x02, 0xaa, 0xbb]));
}

#[test]
fn padding_produces_an_exact_multiple_and_is_idempotent() {
    let mut wire = MessageBuilder::reply_to(&query())
        .expect("reply")
        .with_opt(OptBuilder::new(1232))
        .finish()
        .expect("wire");
    let unpadded = wire.len();

    assert!(pad_to_block(&mut wire, 128));
    assert_eq!(wire.len() % 128, 0);
    assert!(wire.len() > unpadded);
    let info = parse_opt(&wire).expect("OPT");
    let padding: Vec<&Vec<u8>> = info
        .options
        .iter()
        .filter_map(|option| match option {
            EdnsOption::Padding(data) => Some(data),
            _ => None,
        })
        .collect();
    assert_eq!(padding.len(), 1);
    assert!(padding[0].iter().all(|byte| *byte == 0));

    let padded = wire.len();
    assert!(pad_to_block(&mut wire, 128));
    assert_eq!(wire.len(), padded);
    assert_eq!(wire.len() % 128, 0);

    let mut no_opt = query();
    assert!(!pad_to_block(&mut no_opt, 128));
    assert!(!pad_to_block(&mut wire, 0));
}

#[test]
fn truncate_sets_tc_and_keeps_question_and_opt_when_they_fit() {
    let mut wire = {
        let mut builder = MessageBuilder::reply_to(&query())
            .expect("reply")
            .with_opt(OptBuilder::new(1232));
        for index in 0..20u8 {
            builder = builder.push_answer(record(
                "www.example.com.",
                TYPE_A,
                RData::A(Ipv4Addr::new(10, 0, 0, index)),
            ));
        }
        builder.finish().expect("wire")
    };
    assert!(wire.len() > 50);

    assert!(truncate_udp(&mut wire, 50));
    let header = parse_header(&wire).unwrap();
    assert_eq!(header.flags & 0x0200, 0x0200, "TC set");
    assert_eq!(header.question_count, 1);
    assert_eq!(header.answer_count, 0);
    assert_eq!(header.authority_count, 0);
    assert_eq!(header.additional_count, 1);
    assert!(wire.len() <= 50);
    assert!(parse_opt(&wire).is_some());
    assert!(parse_question(&wire, 12, true).is_some());

    // Already within the limit: nothing to do.
    assert!(!truncate_udp(&mut wire, 512));

    // Small enough for the question but not for the 11-byte OPT: the OPT is dropped.
    let mut without_opt = MessageBuilder::reply_to(&query())
        .expect("reply")
        .push_answer(record(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(10, 0, 0, 0)),
        ))
        .with_opt(OptBuilder::new(1232))
        .finish()
        .unwrap();
    assert!(truncate_udp(&mut without_opt, 40));
    assert!(without_opt.len() <= 40);
    assert_eq!(parse_header(&without_opt).unwrap().additional_count, 0);
    assert!(parse_opt(&without_opt).is_none());

    // Even the header and question do not fit: the caller gets a refusal and no change.
    let mut too_small = wire.clone();
    let before = too_small.clone();
    assert!(!truncate_udp(&mut too_small, 10));
    assert_eq!(too_small, before);
}

#[test]
fn rdata_rtype_matches_the_variant() {
    assert_eq!(RData::A(Ipv4Addr::LOCALHOST).rtype(), Some(TYPE_A));
    assert_eq!(RData::Aaaa(Ipv6Addr::LOCALHOST).rtype(), Some(TYPE_AAAA));
    assert_eq!(RData::Cname(String::new()).rtype(), Some(TYPE_CNAME));
    assert_eq!(RData::Ptr(String::new()).rtype(), Some(TYPE_PTR));
    assert_eq!(RData::Ns(String::new()).rtype(), Some(TYPE_NS));
    assert_eq!(RData::Raw(Vec::new()).rtype(), None);
}

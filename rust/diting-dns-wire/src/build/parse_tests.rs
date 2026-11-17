//! Parsed-message tests: full round trips, compression, malformed input, helpers and truncation.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use super::*;

fn rr(name: &str, rtype: u16, rdata: RData) -> ResourceRecord {
    ResourceRecord::new(name, rtype, CLASS_IN, 60, rdata)
}

fn query_wire() -> Vec<u8> {
    MessageBuilder::query("www.example.com.", TYPE_A, CLASS_IN)
        .set_id(0x1234)
        .finish()
        .expect("query")
}

fn reply() -> MessageBuilder {
    MessageBuilder::reply_to(&query_wire()).expect("reply")
}

fn wire_len(parsed: &ParsedMessage, add: bool, auth: bool, ans: bool) -> usize {
    let mut copy = parsed.clone();
    if !add {
        copy.additionals.clear();
    }
    if !auth {
        copy.authorities.clear();
    }
    if !ans {
        copy.answers.clear();
    }
    copy.to_wire().expect("re-encode").len()
}

#[test]
fn full_message_round_trip() {
    let opt = OptBuilder::new(1232)
        .with_do_bit(true)
        .push_option(EdnsOption::Ede(EdeOption::new(15, "blocked by policy")))
        .push_option(EdnsOption::Ecs(EcsOption::from_ip(
            IpAddr::V4(Ipv4Addr::new(192, 0, 2, 33)),
            24,
            0,
        )));

    let wire = reply()
        .set_authoritative(true)
        .set_recursion_available(true)
        .push_answer(rr(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(192, 0, 2, 1)),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_AAAA,
            RData::Aaaa("2001:db8::1".parse().expect("addr")),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_CNAME,
            RData::Cname("target.example.net.".to_string()),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_TXT,
            RData::txt(["hello", "world"]),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_SOA,
            RData::Soa {
                mname: "ns1.example.com.".to_string(),
                rname: "hostmaster.example.com.".to_string(),
                serial: 2024010101,
                refresh: 7200,
                retry: 3600,
                expire: 1209600,
                minimum: 300,
            },
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_MX,
            RData::Mx {
                preference: 10,
                exchange: "mail.example.com.".to_string(),
            },
        ))
        .push_answer(rr(
            "_sip._udp.example.com.",
            TYPE_SRV,
            RData::Srv {
                priority: 1,
                weight: 2,
                port: 5060,
                target: "sip.example.com.".to_string(),
            },
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_HTTPS,
            RData::Https(
                SvcbRData::new(1, "alt.example.net.")
                    .push(SvcParam::alpn(&["h2", "h3"]))
                    .push(SvcParam::new(SVCB_KEY_ECH, vec![0xaa, 0xbb])),
            ),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_CAA,
            RData::Caa {
                flags: 0,
                tag: "issue".to_string(),
                value: b"letsencrypt.org".to_vec(),
            },
        ))
        .with_opt(opt)
        .finish()
        .expect("wire");

    let parsed = ParsedMessage::parse(&wire).expect("parse");
    assert_eq!(parsed.id, 0x1234);
    assert!(parsed.is_response());
    assert_eq!(
        parsed.question().expect("question").name,
        "www.example.com."
    );
    assert_eq!(parsed.answers.len(), 9);
    assert!(parsed.authorities.is_empty());
    assert!(parsed.additionals.is_empty(), "OPT is stored separately");
    assert_eq!(parsed.opt.as_ref().expect("OPT").udp_size, 1232);

    assert_eq!(
        parsed.answers[0].rdata,
        RData::A(Ipv4Addr::new(192, 0, 2, 1))
    );
    assert_eq!(
        parsed.answers[1].rdata,
        RData::Aaaa("2001:db8::1".parse().expect("addr"))
    );
    assert_eq!(
        parsed.answers[2].rdata,
        RData::Cname("target.example.net.".to_string())
    );
    assert_eq!(
        parsed.answers[3].rdata,
        RData::Txt(vec![b"hello".to_vec(), b"world".to_vec()])
    );
    assert_eq!(
        parsed.answers[4].rdata,
        RData::Soa {
            mname: "ns1.example.com.".to_string(),
            rname: "hostmaster.example.com.".to_string(),
            serial: 2024010101,
            refresh: 7200,
            retry: 3600,
            expire: 1209600,
            minimum: 300,
        }
    );
    assert_eq!(
        parsed.answers[5].rdata,
        RData::Mx {
            preference: 10,
            exchange: "mail.example.com.".to_string(),
        }
    );
    assert_eq!(
        parsed.answers[6].rdata,
        RData::Srv {
            priority: 1,
            weight: 2,
            port: 5060,
            target: "sip.example.com.".to_string(),
        }
    );
    match &parsed.answers[7].rdata {
        RData::Https(data) => {
            assert_eq!(data.priority, 1);
            assert_eq!(data.target, "alt.example.net.");
            assert_eq!(data.params.len(), 2);
            assert_eq!(data.params[0], SvcParam::alpn(&["h2", "h3"]));
            assert_eq!(
                data.params[1],
                SvcParam::new(SVCB_KEY_ECH, vec![0xaa, 0xbb])
            );
        }
        other => panic!("unexpected HTTPS rdata: {other:?}"),
    }
    assert_eq!(
        parsed.answers[8].rdata,
        RData::Caa {
            flags: 0,
            tag: "issue".to_string(),
            value: b"letsencrypt.org".to_vec(),
        }
    );

    let opt = parsed.opt.as_ref().expect("OPT");
    assert!(opt.do_bit());
    assert_eq!(opt.version(), 0);
    assert_eq!(opt.z(), 0);
    assert_eq!(opt.ext_rcode(), 0);
    assert_eq!(opt.options().len(), 2);
    assert_eq!(
        opt.options()[0],
        EdnsOption::Ede(EdeOption::new(15, "blocked by policy"))
    );
    assert_eq!(
        opt.options()[1],
        EdnsOption::Ecs(EcsOption::new(1, 24, 0, vec![192, 0, 2]))
    );

    let wire2 = parsed.to_wire().expect("re-encode");
    let again = ParsedMessage::parse(&wire2).expect("re-parse");
    assert_eq!(again, parsed);
    assert_eq!(again.to_wire().expect("second encode"), wire2);
}

#[test]
fn compressed_owner_names_round_trip() {
    let wire = reply()
        .push_answer(rr(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(1, 1, 1, 1)),
        ))
        .push_answer(rr(
            "mail.example.com.",
            TYPE_AAAA,
            RData::Aaaa(Ipv6Addr::LOCALHOST),
        ))
        .finish()
        .expect("wire");

    let parsed = ParsedMessage::parse(&wire).expect("parse");
    assert_eq!(parsed.answers[0].name, "www.example.com.");
    assert_eq!(parsed.answers[1].name, "mail.example.com.");
    assert!(
        wire.contains(&0xc0),
        "builder should emit a compression pointer"
    );

    let wire2 = parsed.to_wire().expect("encode");
    let again = ParsedMessage::parse(&wire2).expect("re-parse");
    assert_eq!(again.answers[0].name, "www.example.com.");
    assert_eq!(again.answers[1].name, "mail.example.com.");
    assert_eq!(again.to_wire().expect("second encode"), wire2);
}

#[test]
fn malformed_messages_are_rejected() {
    // Header shorter than the fixed 12 bytes.
    assert!(ParsedMessage::parse(&[]).is_none());
    assert!(ParsedMessage::parse(&[0u8; 11]).is_none());

    // Question cut before its qclass.
    let query = query_wire();
    assert!(ParsedMessage::parse(&query[..query.len() - 1]).is_none());

    // A question name that points at itself.
    let mut pointer_loop = vec![0u8; 12];
    pointer_loop[4..6].copy_from_slice(&1u16.to_be_bytes());
    pointer_loop.extend_from_slice(&[0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01]);
    assert!(ParsedMessage::parse(&pointer_loop).is_none());

    // CNAME rdata claims a 3-byte label but the rdata is only one byte long.
    let mut truncated_rdata = vec![0u8; 12];
    truncated_rdata[6..8].copy_from_slice(&1u16.to_be_bytes());
    truncated_rdata.push(0); // root owner
    truncated_rdata.extend_from_slice(&TYPE_CNAME.to_be_bytes());
    truncated_rdata.extend_from_slice(&CLASS_IN.to_be_bytes());
    truncated_rdata.extend_from_slice(&0u32.to_be_bytes());
    truncated_rdata.extend_from_slice(&1u16.to_be_bytes());
    truncated_rdata.push(0x03);
    assert!(ParsedMessage::parse(&truncated_rdata).is_none());

    // RDLENGTH runs past the end of the message.
    let mut past_end = vec![0u8; 12];
    past_end[6..8].copy_from_slice(&1u16.to_be_bytes());
    past_end.push(0);
    past_end.extend_from_slice(&TYPE_A.to_be_bytes());
    past_end.extend_from_slice(&CLASS_IN.to_be_bytes());
    past_end.extend_from_slice(&0u32.to_be_bytes());
    past_end.extend_from_slice(&4u16.to_be_bytes());
    assert!(ParsedMessage::parse(&past_end).is_none());

    // Header counts that the message cannot satisfy.
    let mut two_questions = query_wire();
    two_questions[4..6].copy_from_slice(&2u16.to_be_bytes());
    assert!(ParsedMessage::parse(&two_questions).is_none());

    let mut phantom_answer = query_wire();
    phantom_answer[6..8].copy_from_slice(&1u16.to_be_bytes());
    assert!(ParsedMessage::parse(&phantom_answer).is_none());
}

#[test]
fn record_helpers_and_edns_mutation() {
    let wire = reply()
        .push_answer(rr(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(203, 0, 113, 9)),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_AAAA,
            RData::Aaaa(Ipv6Addr::LOCALHOST),
        ))
        .push_answer(rr(
            "www.example.com.",
            TYPE_CNAME,
            RData::Cname("target.example.".to_string()),
        ))
        .with_opt(
            OptBuilder::new(1232)
                .push_option(EdnsOption::Ede(EdeOption::new(1, "one")))
                .push_option(EdnsOption::Ecs(EcsOption::new(
                    1,
                    24,
                    0,
                    vec![198, 51, 100],
                ))),
        )
        .finish()
        .expect("wire");

    let mut parsed = ParsedMessage::parse(&wire).expect("parse");
    assert_eq!(
        parsed.answer_addrs(),
        vec![
            IpAddr::V4(Ipv4Addr::new(203, 0, 113, 9)),
            IpAddr::V6(Ipv6Addr::LOCALHOST),
        ]
    );
    assert_eq!(parsed.answer_cnames(), vec!["target.example.".to_string()]);

    assert_eq!(parsed.opt_options().len(), 2);
    assert!(parsed.remove_opt_option(OPTION_EDE));
    assert_eq!(
        parsed.opt_options(),
        &[EdnsOption::Ecs(EcsOption::new(
            1,
            24,
            0,
            vec![198, 51, 100]
        ))]
    );
    assert!(!parsed.remove_opt_option(OPTION_EDE));
    assert!(!parsed.remove_opt_option(65000));

    parsed.push_opt_option(EdnsOption::Ede(EdeOption::new(2, "two")));
    assert_eq!(parsed.opt_options().len(), 2);
    assert_eq!(
        parsed.opt_options()[1],
        EdnsOption::Ede(EdeOption::new(2, "two"))
    );

    let taken = parsed.take_opt().expect("OPT");
    assert_eq!(taken.options.len(), 2);
    assert!(parsed.opt.is_none());
    assert!(parsed.opt_options().is_empty());

    // A message without OPT gets one on demand with the default payload size.
    let plain = reply()
        .push_answer(rr(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(192, 0, 2, 7)),
        ))
        .finish()
        .expect("wire");
    let mut plain = ParsedMessage::parse(&plain).expect("parse");
    assert!(plain.opt.is_none());
    plain.push_opt_option(EdnsOption::Nsid(b"server-1".to_vec()));
    assert_eq!(plain.opt.as_ref().expect("OPT").udp_size(), 1232);
    assert_eq!(
        plain.opt_options(),
        &[EdnsOption::Nsid(b"server-1".to_vec())]
    );
}

#[test]
fn truncate_drops_sections_in_order_and_sets_tc() {
    let wire = reply()
        .push_answer(rr(
            "www.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(192, 0, 2, 1)),
        ))
        .push_authority(rr(
            "example.com.",
            TYPE_NS,
            RData::Ns("ns1.example.com.".to_string()),
        ))
        .push_additional(rr(
            "ns1.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(192, 0, 2, 53)),
        ))
        .push_additional(rr(
            "ns2.example.com.",
            TYPE_A,
            RData::A(Ipv4Addr::new(192, 0, 2, 54)),
        ))
        .with_opt(OptBuilder::new(1232))
        .finish()
        .expect("wire");

    let parsed = ParsedMessage::parse(&wire).expect("parse");
    assert_eq!(parsed.answers.len(), 1);
    assert_eq!(parsed.authorities.len(), 1);
    assert_eq!(parsed.additionals.len(), 2);
    assert!(parsed.opt.is_some());

    // Already fits: no TC, no change.
    let full = wire_len(&parsed, true, true, true);
    let mut untouched = parsed.clone();
    assert!(!untouched.truncate_to(full));
    assert_eq!(untouched.flags & 0x0200, 0);

    // Drop both additionals, keep authority and answer.
    let max_no_add = wire_len(&parsed, false, true, true);
    let mut no_add = parsed.clone();
    assert!(no_add.truncate_to(max_no_add));
    assert!(no_add.additionals.is_empty());
    assert_eq!(no_add.authorities.len(), 1);
    assert_eq!(no_add.answers.len(), 1);
    assert_ne!(no_add.flags & 0x0200, 0, "TC set");
    assert!(no_add.opt.is_some(), "OPT is not an ordinary additional");
    assert!(no_add.to_wire().expect("encode").len() <= max_no_add);

    // Drop additionals and authority, keep the answer.
    let max_no_auth = wire_len(&parsed, false, false, true);
    let mut no_auth = parsed.clone();
    assert!(no_auth.truncate_to(max_no_auth));
    assert!(no_auth.additionals.is_empty());
    assert!(no_auth.authorities.is_empty());
    assert_eq!(no_auth.answers.len(), 1);

    // Drop everything but the question and OPT.
    let max_no_answers = wire_len(&parsed, false, false, false);
    let mut bare = parsed.clone();
    assert!(bare.truncate_to(max_no_answers));
    assert!(bare.answers.is_empty());
    assert!(bare.authorities.is_empty());
    assert!(bare.additionals.is_empty());
    assert_eq!(bare.questions.len(), 1);
    assert!(bare.opt.is_some());
    assert!(bare.to_wire().expect("encode").len() <= max_no_answers);
}

#[test]
fn unknown_rdata_survives_as_raw() {
    let raw = vec![0xde, 0xad, 0xbe, 0xef];
    let wire = reply()
        .push_answer(rr("www.example.com.", 0xff00, RData::Raw(raw.clone())))
        .finish()
        .expect("wire");

    let parsed = ParsedMessage::parse(&wire).expect("parse");
    assert_eq!(parsed.answers[0].rtype, 0xff00);
    assert_eq!(parsed.answers[0].rdata, RData::Raw(raw.clone()));

    let wire2 = parsed.to_wire().expect("encode");
    let again = ParsedMessage::parse(&wire2).expect("re-parse");
    assert_eq!(again.answers[0].rdata, RData::Raw(raw));
    assert_eq!(again.to_wire().expect("second encode"), wire2);
}

#[test]
fn extended_rcode_is_split_across_header_and_opt() {
    let wire = reply().finish().expect("wire");
    let mut parsed = ParsedMessage::parse(&wire).expect("parse");

    parsed.set_rcode(3);
    assert_eq!(parsed.rcode(), 3);
    assert!(parsed.opt.is_none(), "small rcodes need no OPT");

    parsed.set_rcode(0x20);
    assert_eq!(parsed.flags & 0x000f, 0);
    assert_eq!(parsed.opt.as_ref().expect("OPT").ext_rcode(), 2);
    assert_eq!(parsed.rcode(), 0x20);

    let again = ParsedMessage::parse(&parsed.to_wire().expect("encode")).expect("re-parse");
    assert_eq!(again.rcode(), 0x20);

    parsed.set_rcode(2);
    assert_eq!(parsed.rcode(), 2);
    assert_eq!(parsed.opt.as_ref().expect("OPT").ext_rcode(), 0);
}

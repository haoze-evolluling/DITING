use super::*;
use diting_dns_wire::unpack_name;

fn name_wire(name: &str) -> Vec<u8> {
    let mut out = Vec::new();
    for label in name
        .trim_end_matches('.')
        .split('.')
        .filter(|l| !l.is_empty())
    {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out
}

fn query(name: &str, qtype: u16) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x1234u16.to_be_bytes());
    out.extend(0x0100u16.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire(name));
    out.extend(qtype.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out
}

fn answer(wire: &mut Vec<u8>, name: &str, rrtype: u16, ttl: u32, rdata: &[u8]) {
    wire.extend(name_wire(name));
    wire.extend(rrtype.to_be_bytes());
    wire.extend(1u16.to_be_bytes());
    wire.extend(ttl.to_be_bytes());
    wire.extend((rdata.len() as u16).to_be_bytes());
    wire.extend_from_slice(rdata);
}

fn response(answers: Vec<(String, u16, u32, Vec<u8>)>) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x1234u16.to_be_bytes());
    out.extend(0x8180u16.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend((answers.len() as u16).to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(0u16.to_be_bytes());
    out.extend(name_wire("target.example."));
    out.extend(TYPE_A.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    for (name, rrtype, ttl, rdata) in answers {
        answer(&mut out, &name, rrtype, ttl, &rdata);
    }
    out
}

fn cname_target(record: &ReplyRecord) -> String {
    String::from_utf8(record.rdata.clone()).expect("CNAME target")
}

#[test]
fn block_custom_ip_matches_the_question_family() {
    let plan = block(&query("ads.example.", TYPE_A), RESPONSE_CUSTOM_IP).unwrap();
    assert_eq!(plan.rcode, RCODE_SUCCESS);
    assert!(!plan.recursion_available);
    assert_eq!(
        plan.answers,
        vec![ReplyRecord {
            rrtype: TYPE_A,
            class: CLASS_INET,
            ttl: REWRITE_ANSWER_TTL,
            name: "ads.example.".to_string(),
            rdata: vec![0, 0, 0, 0],
        }]
    );

    let v6 = block(&query("ads.example.", TYPE_AAAA), RESPONSE_CUSTOM_IP).unwrap();
    assert_eq!(v6.answers[0].rdata, vec![0u8; 16]);

    let txt = block(&query("ads.example.", 16), RESPONSE_CUSTOM_IP).unwrap();
    assert!(txt.answers.is_empty());
}

#[test]
fn block_modes_map_to_the_old_rcodes() {
    let q = query("ads.example.", TYPE_A);
    assert_eq!(block(&q, RESPONSE_NXDOMAIN).unwrap().rcode, RCODE_NXDOMAIN);
    assert_eq!(block(&q, RESPONSE_REFUSED).unwrap().rcode, RCODE_REFUSED);
    let nodata = block(&q, RESPONSE_NO_DATA).unwrap();
    assert_eq!(nodata.rcode, RCODE_SUCCESS);
    assert!(nodata.answers.is_empty());
}

#[test]
fn local_asset_answers_a_only() {
    let plan = local_asset(&query("local.pwhs.app.", TYPE_A)).unwrap();
    assert_eq!(plan.answers.len(), 1);
    assert_eq!(plan.answers[0].rdata, LOCAL_ASSET_IPV4.to_vec());

    let v6 = local_asset(&query("local.pwhs.app.", TYPE_AAAA)).unwrap();
    assert!(v6.answers.is_empty());
    assert_eq!(v6.rcode, RCODE_SUCCESS);
}

#[test]
fn ddr_and_servfail_carry_no_answers() {
    let ddr = ddr(&query("_dns.resolver.arpa.", TYPE_A)).unwrap();
    assert_eq!(ddr.rcode, RCODE_NXDOMAIN);
    assert!(ddr.answers.is_empty());

    let fail = servfail(&query("example.", TYPE_A)).unwrap();
    assert_eq!(fail.rcode, RCODE_SERVFAIL);
    assert!(!fail.recursion_available);
}

#[test]
fn rewrite_ip_advertises_recursion() {
    let plan = rewrite_ip(&query("github.com.", TYPE_A), "140.82.112.3").unwrap();
    assert!(plan.recursion_available);
    assert_eq!(plan.answers[0].rdata, vec![140, 82, 112, 3]);
    assert_eq!(plan.answers[0].ttl, REWRITE_ANSWER_TTL);

    let v6 = rewrite_ip(&query("github.com.", TYPE_AAAA), "2606:50c0:8000::153").unwrap();
    assert_eq!(v6.answers[0].rdata.len(), 16);

    // A mapped IPv6 literal still fills a 4-byte A record (net.IP.To4).
    let mapped = rewrite_ip(&query("github.com.", TYPE_A), "::ffff:1.2.3.4").unwrap();
    assert_eq!(mapped.answers[0].rdata, vec![1, 2, 3, 4]);

    assert!(rewrite_ip(&query("github.com.", TYPE_A), "not-an-ip").is_none());
}

#[test]
fn rewrite_cname_copies_matching_addresses() {
    let resolved = response(vec![
        (
            "target.example.".to_string(),
            TYPE_CNAME,
            60,
            name_wire("cdn.example."),
        ),
        ("cdn.example.".to_string(), TYPE_A, 120, vec![1, 2, 3, 4]),
        ("cdn.example.".to_string(), TYPE_A, 90, vec![5, 6, 7, 8]),
        ("cdn.example.".to_string(), TYPE_AAAA, 60, vec![0x20; 16]),
    ]);

    let plan = rewrite_cname(
        &query("origin.example.", TYPE_A),
        "target.example",
        &resolved,
    )
    .unwrap();
    assert_eq!(plan.answers.len(), 3, "CNAME + two A records");
    assert_eq!(plan.answers[0].rrtype, TYPE_CNAME);
    assert_eq!(plan.answers[0].name, "origin.example.");
    assert_eq!(cname_target(&plan.answers[0]), "target.example.");
    assert_eq!(plan.answers[1].name, "cdn.example.");
    assert_eq!(plan.answers[1].ttl, 120);
    assert_eq!(plan.answers[1].rdata, vec![1, 2, 3, 4]);
    assert_eq!(plan.answers[2].rdata, vec![5, 6, 7, 8]);

    let v6 = rewrite_cname(
        &query("origin.example.", TYPE_AAAA),
        "target.example.",
        &resolved,
    )
    .unwrap();
    assert_eq!(v6.answers.len(), 2);
    assert_eq!(v6.answers[1].rdata, vec![0x20; 16]);
}

#[test]
fn rewrite_cname_falls_through_without_addresses() {
    let resolved = response(vec![(
        "target.example.".to_string(),
        TYPE_A,
        60,
        vec![1, 2, 3, 4],
    )]);
    let plan = rewrite_cname(
        &query("origin.example.", TYPE_AAAA),
        "target.example",
        &resolved,
    )
    .unwrap();
    assert!(plan.is_not_applicable());

    let garbage = rewrite_cname(&query("origin.example.", TYPE_A), "target", b"not-dns").unwrap();
    assert!(garbage.is_not_applicable());
}

#[test]
fn query_without_question_is_rejected() {
    assert!(parse_query(&[]).is_none());
    let header_only = {
        let mut out = query("example.", TYPE_A);
        out[4..6].copy_from_slice(&0u16.to_be_bytes());
        out
    };
    assert!(parse_query(&header_only).is_none());
}

/// `render` reproduces what `SetReply` + `dns.Msg.Pack` produced: the query's id, opcode and RD,
/// the plan's rcode/RA, the question copied verbatim and the answers in order.
#[test]
fn render_writes_the_client_message() {
    let query_wire = query("blocked.example.", TYPE_A);
    let plan = block(&query_wire, RESPONSE_NXDOMAIN).expect("plan");
    let wire = render(&query_wire, &plan).expect("renders");

    assert_eq!(
        &wire[0..2],
        &query_wire[0..2],
        "transaction id is the query's"
    );
    assert_eq!(
        u16::from_be_bytes([wire[2], wire[3]]) & 0x8000,
        0x8000,
        "QR"
    );
    assert_eq!(
        u16::from_be_bytes([wire[2], wire[3]]) & 0x0100,
        0x0100,
        "RD copied"
    );
    assert_eq!(
        u16::from_be_bytes([wire[2], wire[3]]) & 0x000f,
        3,
        "NXDOMAIN"
    );
    assert_eq!(u16::from_be_bytes([wire[4], wire[5]]), 1, "one question");
    assert_eq!(u16::from_be_bytes([wire[6], wire[7]]), 0, "no answers");
    assert_eq!(u16::from_be_bytes([wire[8], wire[9]]), 0, "no authority");
    assert_eq!(u16::from_be_bytes([wire[10], wire[11]]), 0, "no additional");
    assert_eq!(
        &wire[12..],
        &query_wire[12..],
        "the question is copied verbatim"
    );
}

/// The A/AAAA block answers carry the owner name and the address rdata, and the CNAME rewrite
/// carries a packed target name rather than the presentation string.
#[test]
fn render_writes_answer_records() {
    let query_wire = query("blocked.example.", TYPE_A);
    let plan = block(&query_wire, RESPONSE_CUSTOM_IP).expect("plan");
    let wire = render(&query_wire, &plan).expect("renders");
    assert_eq!(u16::from_be_bytes([wire[6], wire[7]]), 1, "one answer");

    let answer_at = 12 + name_wire("blocked.example.").len() + 4;
    let mut offset = answer_at;
    let (name, next) = unpack_name(&wire, offset, wire.len()).expect("owner name");
    assert_eq!(name, "blocked.example.");
    offset = next;
    assert_eq!(u16::from_be_bytes([wire[offset], wire[offset + 1]]), TYPE_A);
    assert_eq!(u16::from_be_bytes([wire[offset + 2], wire[offset + 3]]), 1);
    assert_eq!(
        u32::from_be_bytes([
            wire[offset + 4],
            wire[offset + 5],
            wire[offset + 6],
            wire[offset + 7]
        ]),
        REWRITE_ANSWER_TTL
    );
    assert_eq!(u16::from_be_bytes([wire[offset + 8], wire[offset + 9]]), 4);
    assert_eq!(&wire[offset + 10..offset + 14], &[0, 0, 0, 0]);
    assert_eq!(wire.len(), offset + 14, "nothing trails the answer");

    let resolved = response(vec![(
        "target.example.".into(),
        TYPE_A,
        60,
        vec![1, 2, 3, 4],
    )]);
    let plan = rewrite_cname(&query_wire, "alias.example", &resolved).expect("plan");
    let wire = render(&query_wire, &plan).expect("renders");
    let answer_at = 12 + name_wire("blocked.example.").len() + 4;
    let (_, next) = unpack_name(&wire, answer_at, wire.len()).expect("owner name");
    assert_eq!(u16::from_be_bytes([wire[next], wire[next + 1]]), TYPE_CNAME);
    let length = u16::from_be_bytes([wire[next + 8], wire[next + 9]]) as usize;
    assert_eq!(
        &wire[next + 10..next + 10 + length],
        name_wire("alias.example.").as_slice(),
        "the CNAME target is packed as labels"
    );
}

/// A plan that does not apply, and a query too broken to copy, both refuse to render.
#[test]
fn render_refuses_unusable_input() {
    let query_wire = query("example.", TYPE_A);
    let not_applicable = rewrite_cname(&query_wire, "alias.example", &[]).expect("plan");
    assert!(not_applicable.is_not_applicable());
    assert!(render(&query_wire, &not_applicable).is_none());

    let plan = servfail(&query_wire).expect("plan");
    assert!(render(&[0u8; 4], &plan).is_none());
}

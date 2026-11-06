//! Wire-layer cases: the key format, the record walk and the metadata the cache stores.

use super::*;

const CLASS_IN: u16 = 1;
const TYPE_A: u16 = 1;
const TYPE_CNAME: u16 = 5;
const TYPE_SOA: u16 = 6;
const TYPE_AAAA: u16 = 28;
const TYPE_OPT: u16 = 41;
const TYPE_SVCB: u16 = 64;
const TYPE_HTTPS: u16 = 65;

fn name_wire(name: &str) -> Vec<u8> {
    let trimmed = name.trim_end_matches('.');
    let mut out = Vec::new();
    if trimmed.is_empty() {
        out.push(0);
        return out;
    }
    for label in trimmed.split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out
}

fn header(flags: u16, answers: u16, authority: u16, additional: u16) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend(0x1234u16.to_be_bytes());
    out.extend(flags.to_be_bytes());
    out.extend(1u16.to_be_bytes());
    out.extend(answers.to_be_bytes());
    out.extend(authority.to_be_bytes());
    out.extend(additional.to_be_bytes());
    out
}

fn query_message(name: &str, qtype: u16) -> Vec<u8> {
    let mut out = header(0x0100, 0, 0, 0);
    out.extend(name_wire(name));
    out.extend(qtype.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    out
}

fn record(name: &str, rrtype: u16, ttl: u32, rdata: &[u8]) -> Vec<u8> {
    let mut out = name_wire(name);
    out.extend(rrtype.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    out.extend(ttl.to_be_bytes());
    out.extend((rdata.len() as u16).to_be_bytes());
    out.extend_from_slice(rdata);
    out
}

fn a_record(name: &str, ttl: u32, address: [u8; 4]) -> Vec<u8> {
    record(name, TYPE_A, ttl, &address)
}

fn aaaa_record(name: &str, ttl: u32, address: [u8; 16]) -> Vec<u8> {
    record(name, TYPE_AAAA, ttl, &address)
}

fn cname_record(name: &str, ttl: u32, target: &str) -> Vec<u8> {
    record(name, TYPE_CNAME, ttl, &name_wire(target))
}

fn svcb_record(name: &str, rrtype: u16, ttl: u32, target: &str) -> Vec<u8> {
    let mut rdata = 1u16.to_be_bytes().to_vec();
    rdata.extend(name_wire(target));
    record(name, rrtype, ttl, &rdata)
}

fn opt_record(ttl: u32) -> Vec<u8> {
    record(".", TYPE_OPT, ttl, &[])
}

fn soa_record(name: &str, ttl: u32, minimum: u32) -> Vec<u8> {
    let mut rdata = name_wire("ns1.example.com.");
    rdata.extend(name_wire("hostmaster.example.com."));
    rdata.extend(1u32.to_be_bytes());
    rdata.extend(7200u32.to_be_bytes());
    rdata.extend(3600u32.to_be_bytes());
    rdata.extend(1209600u32.to_be_bytes());
    rdata.extend(minimum.to_be_bytes());
    record(name, TYPE_SOA, ttl, &rdata)
}

fn response(
    flags: u16,
    answers: &[Vec<u8>],
    authority: &[Vec<u8>],
    additional: &[Vec<u8>],
) -> Vec<u8> {
    let mut out = header(
        flags,
        answers.len() as u16,
        authority.len() as u16,
        additional.len() as u16,
    );
    out.extend(name_wire("Query.Example."));
    out.extend(TYPE_AAAA.to_be_bytes());
    out.extend(CLASS_IN.to_be_bytes());
    for rr in answers.iter().chain(authority).chain(additional) {
        out.extend_from_slice(rr);
    }
    out
}

fn ttl_at(wire: &[u8], offset: u16) -> u32 {
    read_u32(wire, offset as usize).expect("offset inside the wire")
}

fn ttl_values(wire: &[u8], offsets: &[u16]) -> Vec<u32> {
    offsets.iter().map(|offset| ttl_at(wire, *offset)).collect()
}

#[test]
fn question_key_lowercases_and_joins_labels() {
    let wire = query_message("Example.COM.", TYPE_AAAA);
    let key = question_key(&wire).expect("valid question");
    assert_eq!(key.key, b"example.com:28:1".to_vec());
    assert_eq!(key.name_len, "example.com".len());
    assert_eq!(key.qtype, TYPE_AAAA);
    assert_eq!(key.qclass, CLASS_IN);
}

#[test]
fn question_key_handles_the_root_name() {
    let wire = query_message(".", TYPE_A);
    let key = question_key(&wire).expect("valid question");
    assert_eq!(key.key, b":1:1".to_vec());
    assert_eq!(key.name_len, 0);
}

#[test]
fn question_key_follows_compression_pointers() {
    // The question points at a name stored after the question's qtype/qclass.
    let mut wire = header(0x0100, 0, 0, 0);
    wire.extend_from_slice(&[0xc0, 0x14]);
    wire.extend(TYPE_A.to_be_bytes());
    wire.extend(CLASS_IN.to_be_bytes());
    wire.extend_from_slice(&[0, 0]);
    wire.extend(name_wire("A."));

    let key = question_key(&wire).expect("compressed question");
    assert_eq!(key.key, b"a:1:1".to_vec());
    assert_eq!(key.name_len, 1);
}

#[test]
fn question_key_rejects_broken_questions() {
    assert_eq!(question_key(&[]), None);
    assert_eq!(question_key(&[0; 11]), None);

    let mut no_question = header(0x0100, 0, 0, 0);
    no_question[4..6].copy_from_slice(&0u16.to_be_bytes());
    assert_eq!(question_key(&no_question), None);

    let mut reserved_label = header(0x0100, 0, 0, 0);
    reserved_label.extend_from_slice(&[0x40, b'a', 0]);
    assert_eq!(question_key(&reserved_label), None);

    let mut truncated_label = header(0x0100, 0, 0, 0);
    truncated_label.extend_from_slice(&[5, b'a']);
    assert_eq!(question_key(&truncated_label), None);

    let mut missing_tail = header(0x0100, 0, 0, 0);
    missing_tail.extend(name_wire("a."));
    missing_tail.extend_from_slice(&[0, 1]);
    assert_eq!(question_key(&missing_tail), None);

    // A pointer loop burns the 64-jump budget and is rejected.
    let mut looped = header(0x0100, 0, 0, 0);
    looped.extend_from_slice(&[0xc0, 0x0c]);
    looped.extend_from_slice(&[0, 0, 0, 0]);
    assert_eq!(question_key(&looped), None);
}

#[test]
fn response_meta_reads_answers() {
    let answers = [
        a_record("query.example.", 300, [1, 2, 3, 4]),
        aaaa_record(
            "query.example.",
            60,
            [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
        ),
        a_record("query.example.", 120, [5, 6, 7, 8]),
    ];
    let wire = response(0x8180, &answers, &[], &[]);
    let meta = parse_response(&wire).expect("valid response");

    assert!(!meta.truncated);
    assert_eq!(meta.rcode, 0);
    assert_eq!(meta.answer_count, 3);
    assert_eq!(meta.min_ttl, Some(60));
    assert_eq!(
        ttl_values(&wire, &meta.answer_ttl_offsets),
        vec![300, 60, 120]
    );
    assert_eq!(meta.authority_ttl_offsets, Vec::<u16>::new());
    assert_eq!(
        meta.ips,
        vec![
            "1.2.3.4".to_string(),
            "2001:db8::1".to_string(),
            "5.6.7.8".to_string()
        ]
    );
    assert_eq!(meta.resolved_ips, "1.2.3.4,2001:db8::1,5.6.7.8");
    assert!(meta.chain_targets.is_empty());
}

#[test]
fn response_meta_dedupes_ips_in_record_order() {
    let answers = [
        a_record("query.example.", 60, [9, 9, 9, 9]),
        a_record("query.example.", 60, [8, 8, 8, 8]),
        a_record("query.example.", 60, [9, 9, 9, 9]),
    ];
    let wire = response(0x8180, &answers, &[], &[]);
    let meta = parse_response(&wire).expect("valid response");
    assert_eq!(meta.ips, vec!["9.9.9.9".to_string(), "8.8.8.8".to_string()]);
    assert_eq!(meta.resolved_ips, "9.9.9.9,8.8.8.8");
}

#[test]
fn response_meta_formats_ipv6_like_go() {
    let answers = [
        aaaa_record("query.example.", 60, [0; 16]),
        aaaa_record(
            "query.example.",
            60,
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
        ),
        aaaa_record(
            "query.example.",
            60,
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 1, 2, 3, 4],
        ),
        aaaa_record(
            "query.example.",
            60,
            [
                0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0x02, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            ],
        ),
        aaaa_record(
            "query.example.",
            60,
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x01, 0x02, 0x03, 0x04],
        ),
    ];
    let wire = response(0x8180, &answers, &[], &[]);
    let meta = parse_response(&wire).expect("valid response");
    assert_eq!(
        meta.ips,
        vec![
            "::".to_string(),
            "::1".to_string(),
            "1.2.3.4".to_string(),
            "fe80::201:203:405:607".to_string(),
            "::1:102:304".to_string(),
        ]
    );
}

#[test]
fn response_meta_accepts_zero_length_records() {
    // miekg/dns treats every rdLength == 0 record as "valid but empty" (`noRdata`), so the cache
    // used to store such answers with no IPs and no chain targets. Keep that behaviour.
    let answers = [
        record("query.example.", TYPE_A, 300, &[]),
        record("query.example.", TYPE_AAAA, 300, &[]),
        record("query.example.", TYPE_CNAME, 300, &[]),
        record("query.example.", TYPE_SVCB, 300, &1u16.to_be_bytes()),
    ];
    let wire = response(0x8180, &answers, &[], &[]);
    let meta = parse_response(&wire).expect("zero-length records are valid");
    assert_eq!(meta.answer_count, 4);
    assert_eq!(meta.min_ttl, Some(300));
    assert_eq!(meta.answer_ttl_offsets.len(), 4);
    assert!(meta.ips.is_empty());
    assert!(meta.chain_targets.is_empty());

    // An empty SOA answers a negative query with its header TTL and MINIMUM zero.
    let wire = response(0x8183, &[], &[record("example.", TYPE_SOA, 30, &[])], &[]);
    let meta = parse_response(&wire).expect("empty SOA is valid");
    assert_eq!(meta.min_ttl, Some(30));
    assert_eq!(ttl_values(&wire, &meta.authority_ttl_offsets), vec![30]);
}

#[test]
fn response_meta_reads_chain_targets() {
    let answers = [
        cname_record("www.example.com.", 300, "WwW.Example.COM."),
        svcb_record("query.example.", TYPE_SVCB, 300, "Svc.Example."),
        svcb_record("query.example.", TYPE_HTTPS, 300, "."),
        svcb_record("query.example.", TYPE_HTTPS, 300, "alt.example."),
    ];
    let wire = response(0x8180, &answers, &[], &[]);
    let meta = parse_response(&wire).expect("valid response");

    let targets: Vec<(&str, ChainKind)> = meta
        .chain_targets
        .iter()
        .map(|target| (target.domain.as_str(), target.kind))
        .collect();
    assert_eq!(
        targets,
        vec![
            ("www.example.com", ChainKind::Cname),
            ("svc.example", ChainKind::Svcb),
            ("alt.example", ChainKind::Svcb),
        ]
    );
}

#[test]
fn response_meta_skips_opt_in_answers_and_falls_back_to_soa() {
    let answers = [a_record("query.example.", 300, [1, 1, 1, 1]), opt_record(5)];
    let authority = [soa_record("example.", 10, 30)];
    let wire = response(0x8180, &answers, &authority, &[]);
    let meta = parse_response(&wire).expect("valid response");

    assert_eq!(meta.answer_count, 2);
    assert_eq!(meta.min_ttl, Some(300));
    assert_eq!(ttl_values(&wire, &meta.answer_ttl_offsets), vec![300]);
    // The answer is positive, so the authority offsets are not used even though they exist.
    assert_eq!(meta.authority_ttl_offsets, Vec::<u16>::new());

    // Only an OPT answer and an SOA authority: the SOA minimum governs the TTL. The answer count
    // is non-zero, so the authority TTL offsets stay unused (the patcher then has nothing to do).
    let wire = response(
        0x8180,
        &[opt_record(5)],
        &[soa_record("example.", 10, 30)],
        &[],
    );
    let meta = parse_response(&wire).expect("valid response");
    assert_eq!(meta.answer_count, 1);
    assert_eq!(meta.min_ttl, Some(10));
    assert!(meta.answer_ttl_offsets.is_empty());
    assert!(meta.authority_ttl_offsets.is_empty());
}

#[test]
fn response_meta_reads_negative_answers() {
    // NXDOMAIN with the SOA in the authority section.
    let authority = [soa_record("example.", 0, 45)];
    let wire = response(0x8183, &[], &authority, &[]);
    let meta = parse_response(&wire).expect("valid response");

    assert_eq!(meta.rcode, 3);
    assert_eq!(meta.answer_count, 0);
    assert_eq!(meta.min_ttl, Some(45));
    assert!(meta.answer_ttl_offsets.is_empty());
    assert_eq!(ttl_values(&wire, &meta.authority_ttl_offsets), vec![0]);

    // The header TTL wins when it is non-zero and smaller than MINIMUM.
    let wire = response(0x8183, &[], &[soa_record("example.", 20, 45)], &[]);
    assert_eq!(parse_response(&wire).unwrap().min_ttl, Some(20));
}

#[test]
fn response_meta_marks_truncated_responses() {
    let wire = response(0x8380, &[], &[], &[]);
    let meta = parse_response(&wire).expect("valid header");
    assert!(meta.truncated);
    assert_eq!(meta.rcode, 0);
}

#[test]
fn response_meta_rejects_malformed_wire() {
    assert_eq!(parse_response(&[]), None);
    assert_eq!(parse_response(&[0; 11]), None);

    // A question that claims more labels than the buffer holds.
    let mut broken_question = header(0x8180, 0, 0, 0);
    broken_question.extend_from_slice(&[9, b'a']);
    assert_eq!(parse_response(&broken_question), None);

    // rdata length past the end of the message.
    let mut broken_rdata = header(0x8180, 1, 0, 0);
    broken_rdata.extend(name_wire("query.example."));
    broken_rdata.extend(TYPE_AAAA.to_be_bytes());
    broken_rdata.extend(CLASS_IN.to_be_bytes());
    broken_rdata.extend(name_wire("query.example."));
    broken_rdata.extend(TYPE_A.to_be_bytes());
    broken_rdata.extend(CLASS_IN.to_be_bytes());
    broken_rdata.extend(300u32.to_be_bytes());
    broken_rdata.extend(8u16.to_be_bytes());
    broken_rdata.extend_from_slice(&[1, 2, 3, 4]);
    assert_eq!(parse_response(&broken_rdata), None);

    // A CNAME whose name does not fill its rdata.
    let mut rdata = name_wire("target.example.");
    rdata.push(0);
    let answers = [record("query.example.", TYPE_CNAME, 60, &rdata)];
    assert!(parse_response(&response(0x8180, &answers, &[], &[])).is_none());

    // A SOA record whose rdata stops in the middle of a 32-bit field.
    let mut partial_soa = name_wire("ns1.example.");
    partial_soa.extend_from_slice(&[0, 1]);
    assert!(parse_response(&response(
        0x8183,
        &[],
        &[record("example.", TYPE_SOA, 60, &partial_soa)],
        &[]
    ))
    .is_none());

    // A compression pointer loop in an owner name burns the pointer budget.
    let mut looped = header(0x8180, 1, 0, 0);
    looped[4..6].copy_from_slice(&0u16.to_be_bytes());
    looped.extend_from_slice(&[0xc0, 0x0c]);
    looped.extend(TYPE_A.to_be_bytes());
    looped.extend(CLASS_IN.to_be_bytes());
    looped.extend(60u32.to_be_bytes());
    looped.extend(4u16.to_be_bytes());
    looped.extend_from_slice(&[1, 2, 3, 4]);
    assert!(parse_response(&looped).is_none());
}

#[test]
fn patch_response_replaces_id_and_ttls() {
    let answers = [a_record("query.example.", 300, [1, 2, 3, 4])];
    let wire = response(0x8180, &answers, &[], &[]);
    let meta = parse_response(&wire).expect("valid response");

    let patched = patch_response(&wire, &meta.answer_ttl_offsets, 0xbeef, 42).expect("patched");
    assert_eq!(&patched[0..2], &0xbeefu16.to_be_bytes());
    assert_eq!(ttl_at(&patched, meta.answer_ttl_offsets[0]), 42);
    // The original stays untouched: the cache keeps the upstream TTL for later hits.
    assert_eq!(&wire[0..2], &0x1234u16.to_be_bytes());
    assert_eq!(ttl_at(&wire, meta.answer_ttl_offsets[0]), 300);

    let mut out = vec![0u8; wire.len()];
    assert!(patch_response_into(&wire, &[], 7, 1, &mut out));
    assert_eq!(&out[0..2], &7u16.to_be_bytes());
    assert_eq!(ttl_at(&out, meta.answer_ttl_offsets[0]), 300);
}

#[test]
fn patch_response_ignores_out_of_range_offsets() {
    let wire = response(
        0x8180,
        &[a_record("query.example.", 60, [1, 2, 3, 4])],
        &[],
        &[],
    );
    let patched = patch_response(&wire, &[0xfff0, 0xfffe], 1, 9).expect("patched");
    assert_eq!(&patched[0..2], &1u16.to_be_bytes());
    assert_eq!(patched.len(), wire.len());
}

#[test]
fn patch_response_rejects_short_wire_and_small_output() {
    assert_eq!(patch_response(&[0; 11], &[], 1, 1), None);
    let wire = response(0x8180, &[], &[], &[]);
    let mut out = vec![0u8; wire.len() - 1];
    assert!(!patch_response_into(&wire, &[], 1, 1, &mut out));
}

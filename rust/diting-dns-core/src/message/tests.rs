//! Unit tests for the message kernel; `tests/corpus.rs` replays the wire corpus generated from
//! the original Go implementation.

use super::*;

fn header(id: u16, flags: u16, qd: u16, an: u16, ns: u16, ar: u16) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&id.to_be_bytes());
    out.extend_from_slice(&flags.to_be_bytes());
    out.extend_from_slice(&qd.to_be_bytes());
    out.extend_from_slice(&an.to_be_bytes());
    out.extend_from_slice(&ns.to_be_bytes());
    out.extend_from_slice(&ar.to_be_bytes());
    out
}

fn question(name: &str, qtype: u16) -> Vec<u8> {
    let mut out = Vec::new();
    for label in name.trim_end_matches('.').split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out.extend_from_slice(&qtype.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out
}

fn record(owner: &str, rrtype: u16, ttl: u32, rdata: &[u8]) -> Vec<u8> {
    let mut out = question(owner, 0)[..question(owner, 0).len() - 4].to_vec();
    out.extend_from_slice(&rrtype.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&ttl.to_be_bytes());
    out.extend_from_slice(&(rdata.len() as u16).to_be_bytes());
    out.extend_from_slice(rdata);
    out
}

fn query(name: &str, qtype: u16) -> Vec<u8> {
    let mut out = header(0x1234, 0x0100, 1, 0, 0, 0);
    out.extend_from_slice(&question(name, qtype));
    out
}

fn a_answer(name: &str, address: [u8; 4]) -> Vec<u8> {
    let mut out = header(0x1234, 0x8180, 1, 1, 0, 0);
    out.extend_from_slice(&question(name, TYPE_A));
    out.extend_from_slice(&record(name, TYPE_A, 60, &address));
    out
}

#[test]
fn query_info_lowercases_and_drops_the_trailing_dot() {
    let info = query_info(&query("Example.COM.", TYPE_A));
    assert_eq!(
        info,
        QueryInfo {
            name: "example.com".to_string(),
            qtype: TYPE_A,
            valid: true,
        }
    );
    let empty = header(1, 0, 0, 0, 0, 0);
    assert_eq!(query_info(&empty), QueryInfo::invalid());
    let mut response_bit = query("example.com.", TYPE_A);
    response_bit[2] |= 0x80;
    assert_eq!(query_info(&response_bit), QueryInfo::invalid());
}

#[test]
fn validate_accepts_noerror_and_nxdomain_and_rejects_other_rcodes() {
    let q = query("example.com.", TYPE_A);
    assert_eq!(
        validate(&q, &a_answer("example.com.", [1, 2, 3, 4])),
        Validation {
            status: status::ACCEPTED,
            rcode: 0
        }
    );

    let mut nxdomain = a_answer("example.com.", [1, 2, 3, 4]);
    nxdomain[3] = 0x83; // rcode 3, keep the QR bit
    assert_eq!(
        validate(&q, &nxdomain),
        Validation {
            status: status::ACCEPTED,
            rcode: 0
        }
    );

    let mut servfail = a_answer("example.com.", [1, 2, 3, 4]);
    servfail[3] = 0x82;
    assert_eq!(
        validate(&q, &servfail),
        Validation {
            status: status::UPSTREAM_RCODE,
            rcode: 2
        }
    );

    let mut wrong_id = a_answer("example.com.", [1, 2, 3, 4]);
    wrong_id[0] = 0;
    assert_eq!(validate(&q, &wrong_id).status, status::TRANSACTION_MISMATCH);

    assert_eq!(
        validate(&q, &header(0x1234, 0x8183, 1, 0, 0, 0)).status,
        status::QUESTION_COUNT,
        "a header-only refusal has no question section"
    );
}

#[test]
fn validate_compares_the_question_section_case_insensitively() {
    let q = query("example.com.", TYPE_A);
    let mut reply = a_answer("EXAMPLE.COM.", [1, 2, 3, 4]);
    assert_eq!(validate(&q, &reply).status, status::ACCEPTED);
    reply = a_answer("other.example.", [1, 2, 3, 4]);
    assert_eq!(validate(&q, &reply).status, status::QUESTION_MISMATCH);
}

#[test]
fn extract_reports_addresses_ttls_and_the_null_block_verdict() {
    let mut wire = header(0x1234, 0x8180, 1, 2, 0, 0);
    wire.extend_from_slice(&question("example.com.", TYPE_A));
    wire.extend_from_slice(&record("example.com.", TYPE_A, 5, &[0, 0, 0, 0]));
    wire.extend_from_slice(&record("example.com.", TYPE_AAAA, 7, &[0u8; 16]));

    let extracted = extract(&wire).expect("valid answer");
    assert_eq!(extracted.rcode, 0);
    assert!(extracted.blocked);
    assert_eq!(extracted.resolved_ips, "0.0.0.0,::");
    assert_eq!(extracted.ips, vec!["0.0.0.0", "::"]);
    assert_eq!(extracted.question_name, "example.com.");
    assert_eq!(
        extracted.addresses,
        vec![
            AddressRecord {
                rrtype: TYPE_A_BYTE,
                ttl: 5,
                address: vec![0, 0, 0, 0],
            },
            AddressRecord {
                rrtype: TYPE_AAAA_BYTE,
                ttl: 7,
                address: vec![0u8; 16],
            },
        ]
    );
}

#[test]
fn extract_keeps_an_address_less_record_as_nil() {
    let mut wire = header(0x1234, 0x8180, 1, 1, 0, 0);
    wire.extend_from_slice(&question("example.com.", TYPE_A));
    wire.extend_from_slice(&record("example.com.", TYPE_A, 7, &[]));

    let extracted = extract(&wire).expect("noRdata is accepted");
    assert!(!extracted.blocked);
    assert_eq!(extracted.resolved_ips, "<nil>");
    assert_eq!(extracted.addresses[0].address, Vec::<u8>::new());
}

#[test]
fn extract_normalizes_chain_targets() {
    let mut cname = Vec::new();
    cname.extend_from_slice(
        &question("Tracker.Example.ORG.", 0)[..question("Tracker.Example.ORG.", 0).len() - 4],
    );
    let mut wire = header(0x1234, 0x8180, 1, 1, 0, 0);
    wire.extend_from_slice(&question("example.com.", TYPE_A));
    wire.extend_from_slice(&record("example.com.", TYPE_CNAME, 100, &cname));

    let extracted = extract(&wire).expect("valid answer");
    assert_eq!(
        extracted.chain_targets,
        vec![ChainTarget {
            domain: "tracker.example.org".to_string(),
            kind: ChainKind::Cname,
        }]
    );
}

#[test]
fn extract_reads_the_edns_extended_rcode() {
    let mut opt = header(0, 0, 0, 0, 0, 0);
    opt.clear();
    opt.extend_from_slice(&[0u8]); // root owner
    opt.extend_from_slice(&TYPE_OPT.to_be_bytes());
    opt.extend_from_slice(&1232u16.to_be_bytes());
    opt.extend_from_slice(&0x0100_0000u32.to_be_bytes()); // extended rcode 1 -> 16
    opt.extend_from_slice(&0u16.to_be_bytes());

    let mut wire = header(0x1234, 0x8180, 1, 0, 0, 1);
    wire.extend_from_slice(&question("example.com.", TYPE_A));
    wire.extend_from_slice(&opt);

    assert_eq!(extract(&wire).expect("valid").rcode, 16);
    assert_eq!(validate(&query("example.com.", TYPE_A), &wire).rcode, 16);
}

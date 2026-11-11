//! DNS wire work for the diagnostics tools: the A/AAAA query `DnsServerProbe` /
//! `DnsLatencyTester` built by hand in Kotlin, the "did the resolver answer" check, the custom
//! server's answer walk, and the DoH endpoint derivation.
//!
//! The answer walk reuses [`diting_dns_wire::parse_answer_records`] — the same reader the DNS cache
//! and the DNS message kernel use — instead of keeping a second `DataInputStream` parser in Kotlin.

use diting_dns_wire::parse_answer_records;

const HEADER_LEN: usize = 12;
const TYPE_A: u16 = 1;
const TYPE_CNAME: u16 = 5;
const TYPE_AAAA: u16 = 28;
const CLASS_IN: u16 = 1;

/// `DnsServerProbe` / `DnsLatencyTester`'s binary question type.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum QueryType {
    A,
    Aaaa,
}

impl QueryType {
    pub fn from_flag(flag: u8) -> Option<Self> {
        match flag {
            0 => Some(Self::A),
            1 => Some(Self::Aaaa),
            _ => None,
        }
    }

    fn wire(self) -> u16 {
        match self {
            Self::A => TYPE_A,
            Self::Aaaa => TYPE_AAAA,
        }
    }
}

/// Builds one single-question query with `RD = 1`.
///
/// None means a label was empty or longer than 63 bytes, which the Kotlin caller turned into
/// `域名标签非法: <domain>`. Labels are cut the way `String.toByteArray(US_ASCII)` did: every
/// non-ASCII character becomes `?`, one per code point.
pub fn build_query(id: u16, qtype: QueryType, domain: &str) -> Option<Vec<u8>> {
    let trimmed = domain.trim_matches('.');
    let mut query = Vec::with_capacity(HEADER_LEN + trimmed.len() + 6);

    query.extend_from_slice(&id.to_be_bytes());
    query.extend_from_slice(&0x0100u16.to_be_bytes()); // RD = 1
    query.extend_from_slice(&1u16.to_be_bytes()); // QDCOUNT
    query.extend_from_slice(&[0u8; 6]); // ANCOUNT + NSCOUNT + ARCOUNT

    for label in trimmed.split('.') {
        let mut bytes = Vec::with_capacity(label.len());
        for c in label.chars() {
            let code = c as u32;
            bytes.push(if code < 0x80 { code as u8 } else { b'?' });
        }
        if bytes.is_empty() || bytes.len() > 63 {
            return None;
        }
        query.push(bytes.len() as u8);
        query.extend_from_slice(&bytes);
    }
    query.push(0); // end of QNAME
    query.extend_from_slice(&qtype.wire().to_be_bytes());
    query.extend_from_slice(&CLASS_IN.to_be_bytes());
    Some(query)
}

/// `DnsLatencyTester.isSuccess`: `QR = 1` and `RCODE = 0`, read from the fixed header only.
pub fn response_succeeded(wire: &[u8]) -> bool {
    if wire.len() < HEADER_LEN {
        return false;
    }
    let qr = wire[2] & 0x80 != 0;
    let rcode = wire[3] & 0x0F;
    qr && rcode == 0
}

/// One A/AAAA answer of a custom server's reply.
#[derive(Debug, Clone, PartialEq)]
pub struct Answer {
    pub ipv4: bool,
    pub ttl: u32,
    pub value: String,
}

/// Outcome of reading one custom server's reply.
///
/// The four failure kinds are the four exception paths the Kotlin implementation had, kept apart
/// because they print different messages: a short or non-response body, a truncated answer, an
/// error rcode, and an answer section that ends before its declared records (where
/// `DataInputStream` threw an `EOFException` with no message).
#[derive(Debug, Clone, PartialEq)]
pub enum Reply {
    Ok(Vec<Answer>),
    Invalid,
    Truncated,
    Rcode(u8),
    Incomplete,
}

/// Reads the answer section of one reply, keeping only `IN` A/AAAA records of the requested family.
pub fn parse_server_reply(wire: &[u8], ipv4: bool) -> Reply {
    // `wire[0] & 0x80`: the Kotlin check read the *first* byte, which is the high bit of the
    // transaction ID rather than the QR flag in byte 2. It rejects about half of the replies, but
    // fixing it here would change which lookups succeed, so the migration keeps it (see the
    // "已知边界" section of rust/README.md).
    if wire.len() < HEADER_LEN || wire[0] & 0x80 == 0 {
        return Reply::Invalid;
    }
    if wire[2] & 0x02 != 0 {
        return Reply::Truncated;
    }
    let rcode = wire[3] & 0x0F;
    if rcode != 0 {
        return Reply::Rcode(rcode);
    }

    let declared = u16::from_be_bytes([wire[6], wire[7]]) as usize;
    let records = match parse_answer_records(wire) {
        Some(records) => records,
        None => return Reply::Incomplete,
    };
    if records.len() < declared {
        // The header promised more records than the datagram carried; the old reader hit EOF here.
        return Reply::Incomplete;
    }

    let mut answers = Vec::new();
    for record in records {
        if record.class != CLASS_IN {
            continue;
        }
        match record.rrtype {
            TYPE_A if ipv4 && record.rdata.len() == 4 => answers.push(Answer {
                ipv4: true,
                ttl: record.ttl,
                value: format_ipv4(&record.rdata),
            }),
            TYPE_AAAA if !ipv4 && record.rdata.len() == 16 => answers.push(Answer {
                ipv4: false,
                ttl: record.ttl,
                value: format_ipv6(&record.rdata),
            }),
            // CNAME is walked but never rendered, exactly like the Kotlin reader.
            TYPE_CNAME => {}
            _ => {}
        }
    }
    Reply::Ok(answers)
}

/// `(bytes[0] and 0xFF).joinToString(".")`.
pub fn format_ipv4(bytes: &[u8]) -> String {
    format!("{}.{}.{}.{}", bytes[0], bytes[1], bytes[2], bytes[3])
}

/// The Kotlin `formatIpv6`: eight lowercase hex groups, the longest run of two or more zero groups
/// compressed to `::`, no IPv4-mapped special case.
///
/// Deliberately not [`diting_dns_wire::format_ipv6`]: that one prints `net.IP.String()`, which folds
/// `::ffff:a.b.c.d` to `a.b.c.d` for the Go engine. The probe used to print it in hex and the
/// diagnostics panels show whatever came back, so this stays a separate formatter.
pub fn format_ipv6(bytes: &[u8]) -> String {
    let mut groups = [0u16; 8];
    for (index, group) in groups.iter_mut().enumerate() {
        *group = u16::from_be_bytes([bytes[index * 2], bytes[index * 2 + 1]]);
    }

    let mut best_start = 0usize;
    let mut best_length = 0usize;
    let mut index = 0usize;
    while index < 8 {
        if groups[index] != 0 {
            index += 1;
            continue;
        }
        let mut end = index;
        while end < 8 && groups[end] == 0 {
            end += 1;
        }
        if end - index > best_length {
            best_start = index;
            best_length = end - index;
        }
        index = end;
    }

    let hex = |groups: &[u16]| {
        groups
            .iter()
            .map(|group| format!("{group:x}"))
            .collect::<Vec<_>>()
            .join(":")
    };
    if best_length < 2 {
        return hex(&groups);
    }
    let head = hex(&groups[..best_start]);
    let tail = hex(&groups[best_start + best_length..]);
    format!("{head}::{tail}")
}

/// `DnsLatencyTester`'s DoH endpoint: an explicit URL wins, a host that already carries a scheme is
/// used as it is, everything else becomes `https://<host>/dns-query`.
pub fn doh_endpoint(url: &str, host: &str) -> String {
    if !url.trim().is_empty() {
        return url.to_string();
    }
    if host.starts_with("http") {
        return host.to_string();
    }
    format!("https://{host}/dns-query")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    fn build_reply(rcode: u8, answers: &[(u16, u16, u32, Vec<u8>)]) -> Vec<u8> {
        let mut wire = vec![0u8; HEADER_LEN];
        // ID high bit set: `parse_server_reply` tests that bit (see its comment).
        wire[0] = 0x81;
        wire[1] = 0x34;
        wire[2] = 0x81; // QR = 1
        wire[3] = 0x80 | rcode;
        wire[5] = 1; // QDCOUNT = 1
        wire[6..8].copy_from_slice(&(answers.len() as u16).to_be_bytes());
        // One question, compression-free: q.example.com A IN.
        wire.extend_from_slice(&[
            1, b'q', 7, b'e', b'x', b'a', b'm', b'p', b'l', b'e', 3, b'c', b'o', b'm', 0,
        ]);
        wire.extend_from_slice(&TYPE_A.to_be_bytes());
        wire.extend_from_slice(&CLASS_IN.to_be_bytes());
        for (rrtype, class, ttl, rdata) in answers {
            wire.push(0xC0);
            wire.push(0x0C); // pointer back to the question name
            wire.extend_from_slice(&rrtype.to_be_bytes());
            wire.extend_from_slice(&class.to_be_bytes());
            wire.extend_from_slice(&ttl.to_be_bytes());
            wire.extend_from_slice(&(rdata.len() as u16).to_be_bytes());
            wire.extend_from_slice(rdata);
        }
        wire
    }

    #[test]
    fn build_query_matches_the_kotlin_layout() {
        let query = build_query(0xABCD, QueryType::A, "example.com").unwrap();
        assert_eq!(
            hex(&query),
            "abcd01000001000000000000076578616d706c6503636f6d0000010001"
        );
        let aaaa = build_query(0xABCD, QueryType::Aaaa, "example.com.").unwrap();
        assert_eq!(
            hex(&aaaa),
            "abcd01000001000000000000076578616d706c6503636f6d00001c0001"
        );
        // `trim('.')` takes both ends, so a single label is enough.
        assert_eq!(
            hex(&build_query(0, QueryType::A, ".com.").unwrap()),
            "00000100000100000000000003636f6d0000010001"
        );
    }

    #[test]
    fn build_query_rejects_bad_labels() {
        // "." trims to the empty string, whose single label is empty.
        assert!(build_query(0, QueryType::A, ".").is_none());
        assert!(build_query(0, QueryType::A, "").is_none());
        assert!(build_query(0, QueryType::A, "a..b").is_none());
        assert!(build_query(0, QueryType::A, &"a".repeat(64)).is_none());
        assert!(build_query(0, QueryType::A, &"a".repeat(63)).is_some());
        // Non-ASCII becomes `?` per code point, like `toByteArray(US_ASCII)`.
        let query = build_query(0, QueryType::A, "ü.com").unwrap();
        assert_eq!(query[12], 1);
        assert_eq!(query[13], b'?');
    }

    #[test]
    fn response_succeeded_reads_the_fixed_header() {
        assert!(!response_succeeded(&[0u8; 11]));
        let mut wire = build_reply(0, &[]);
        assert!(response_succeeded(&wire));
        wire[3] = 0x80 | 3;
        assert!(!response_succeeded(&wire));
        wire[2] = 0x01; // no QR
        wire[3] = 0x80;
        assert!(!response_succeeded(&wire));
    }

    #[test]
    fn server_reply_keeps_only_the_requested_family() {
        let reply = build_reply(
            0,
            &[
                (TYPE_A, CLASS_IN, 300, vec![1, 2, 3, 4]),
                (TYPE_AAAA, CLASS_IN, 60, {
                    let mut rdata = vec![0u8; 16];
                    rdata[15] = 1;
                    rdata
                }),
                (TYPE_CNAME, CLASS_IN, 60, vec![0xC0, 0x0C]),
                (TYPE_A, 3, 60, vec![5, 6, 7, 8]), // CHAOS class: skipped
                (TYPE_A, CLASS_IN, 60, vec![1, 2, 3]), // wrong length: skipped
            ],
        );
        assert_eq!(
            parse_server_reply(&reply, true),
            Reply::Ok(vec![Answer {
                ipv4: true,
                ttl: 300,
                value: "1.2.3.4".into()
            }])
        );
        assert_eq!(
            parse_server_reply(&reply, false),
            Reply::Ok(vec![Answer {
                ipv4: false,
                ttl: 60,
                value: "::1".into()
            }])
        );
    }

    #[test]
    fn server_reply_reports_the_four_failure_kinds() {
        let mut short = build_reply(0, &[]);
        short.truncate(11);
        assert_eq!(parse_server_reply(&short, true), Reply::Invalid);
        // The Kotlin gate reads the ID high bit, so a reply without it is "incomplete".
        let mut no_id_bit = build_reply(0, &[]);
        no_id_bit[0] = 0x01;
        assert_eq!(parse_server_reply(&no_id_bit, true), Reply::Invalid);
        let mut no_qr = build_reply(0, &[]);
        no_qr[2] &= 0x7F; // cleared QR is *not* rejected by that gate
        assert_eq!(parse_server_reply(&no_qr, true), Reply::Ok(Vec::new()));

        let mut truncated = build_reply(0, &[]);
        truncated[2] |= 0x02;
        assert_eq!(parse_server_reply(&truncated, true), Reply::Truncated);

        assert_eq!(
            parse_server_reply(&build_reply(3, &[]), true),
            Reply::Rcode(3)
        );
        assert_eq!(
            parse_server_reply(&build_reply(15, &[]), true),
            Reply::Rcode(15)
        );

        // Declared two answers, carried one: the old reader hit EOF mid-loop.
        let mut incomplete = build_reply(0, &[(TYPE_A, CLASS_IN, 60, vec![1, 2, 3, 4])]);
        incomplete[7] = 2;
        assert_eq!(parse_server_reply(&incomplete, true), Reply::Incomplete);

        // A question section that runs off the end.
        let mut cut = build_reply(0, &[]);
        cut.truncate(HEADER_LEN + 3);
        assert_eq!(parse_server_reply(&cut, true), Reply::Incomplete);
    }

    #[test]
    fn ipv6_formatting_matches_the_kotlin_groups() {
        let format =
            |text: &str| format_ipv6(&text.parse::<std::net::Ipv6Addr>().unwrap().octets());
        assert_eq!(format("::"), "::");
        assert_eq!(format("::1"), "::1");
        assert_eq!(format("2001:db8::1"), "2001:db8::1");
        assert_eq!(format("2001:db8:0:0:1:0:0:1"), "2001:db8::1:0:0:1");
        assert_eq!(format("1:2:3:4:5:6:7:8"), "1:2:3:4:5:6:7:8");
        assert_eq!(format("0:0:1:0:0:0:0:1"), "0:0:1::1");
        // The first of two equally long zero runs is compressed, and no dotted quad is produced.
        assert_eq!(format("1:0:0:2:0:0:3:4"), "1::2:0:0:3:4");
        assert_eq!(format("::ffff:1.2.3.4"), "::ffff:102:304");
        assert_eq!(format("fe80::abcd:ef01"), "fe80::abcd:ef01");
    }

    #[test]
    fn doh_endpoint_prefers_the_url() {
        assert_eq!(
            doh_endpoint("https://dns.google/dns-query", "ignored"),
            "https://dns.google/dns-query"
        );
        assert_eq!(
            doh_endpoint("", "https://cloudflare-dns.com/dns-query"),
            "https://cloudflare-dns.com/dns-query"
        );
        assert_eq!(doh_endpoint("  ", "1.1.1.1"), "https://1.1.1.1/dns-query");
        assert_eq!(
            doh_endpoint("", "dns.quad9.net"),
            "https://dns.quad9.net/dns-query"
        );
    }
}

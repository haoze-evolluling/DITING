//! Query parsing, upstream answer validation and answer extraction, straight from the wire.
//!
//! This is the resolver half of `android/engine/resolver_strategy.go` and the message walk of
//! `dns_response_helpers.go` / `engine_standalone.go`:
//!
//! * [`query_info`] replaces `parseDNSQuery` (the logged name/type of one query),
//! * [`validate`] replaces `validateDNSResponseParsed` (transaction, question section, rcode
//!   policy),
//! * [`extract`] replaces the `dns.Msg` walk that fed the null-block verdict, the resolved
//!   address list, the CNAME/SVCB chain targets, the app-allowlist grants and the diagnostics
//!   reply.
//!
//! Parsing mirrors `dns.Msg.Unpack`'s leniencies (a message may stop on a record boundary; a
//! question may stop after its name), its header-only shortcut, and the EDNS extended rcode. The
//! one deliberate difference is rdata of record types this kernel does not read: it is skipped by
//! `rdLength` instead of being validated field by field, so a malformed MX/TXT is accepted here
//! while the old Go validator rejected it. Valid answers take the same path as before.

use diting_dns_wire::{
    parse_header, parse_question, read_u16, read_u32, unpack_name, ChainKind, ChainTarget,
    MessageHeader, Question,
};

use crate::answer::{self, AnswerEntry};

/// `dns.TypeA`.
pub const TYPE_A: u16 = 1;
/// `dns.TypeCNAME`.
pub const TYPE_CNAME: u16 = 5;
/// `dns.TypeAAAA`.
pub const TYPE_AAAA: u16 = 28;
/// `dns.TypeOPT`.
pub const TYPE_OPT: u16 = 41;
/// `dns.TypeSVCB`.
pub const TYPE_SVCB: u16 = 64;
/// `dns.TypeHTTPS`.
pub const TYPE_HTTPS: u16 = 65;

/// `dns.TypeA`, as the answer payload spells it.
const TYPE_A_BYTE: u8 = 1;
/// `dns.TypeAAAA`, as the answer payload spells it.
const TYPE_AAAA_BYTE: u8 = 28;

/// The status codes shared with `android/engine/dns_message_payload.go`.
pub mod status {
    /// The answer is usable.
    pub const ACCEPTED: u8 = 0;
    /// The upstream answered with a non-NOERROR/NXDOMAIN rcode.
    pub const UPSTREAM_RCODE: u8 = 1;
    /// The query itself could not be unpacked.
    pub const INVALID_QUERY: u8 = 2;
    /// The query has the QR bit set or no question.
    pub const INVALID_QUERY_FLAGS: u8 = 3;
    /// The response could not be unpacked.
    pub const INVALID_RESPONSE: u8 = 4;
    /// Response bit clear, or a different transaction id.
    pub const TRANSACTION_MISMATCH: u8 = 5;
    /// Wrong number of questions.
    pub const QUESTION_COUNT: u8 = 6;
    /// A question differs in name, type or class.
    pub const QUESTION_MISMATCH: u8 = 7;
}

/// What `parseDNSQuery` returned for logging: the lowercased question name without its trailing
/// dot and the query type. `valid` mirrors "the query unpacked, is not a response and has a
/// question".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueryInfo {
    pub name: String,
    pub qtype: u16,
    pub valid: bool,
}

impl QueryInfo {
    fn invalid() -> Self {
        QueryInfo {
            name: String::new(),
            qtype: TYPE_A,
            valid: false,
        }
    }
}

/// One validation outcome. `rcode` is only meaningful for [`status::UPSTREAM_RCODE`]; an accepted
/// answer keeps its own code on the wire, so Go does not need it here.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Validation {
    pub status: u8,
    pub rcode: u16,
}

/// One A/AAAA record of an answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AddressRecord {
    /// 1 for A, 28 for AAAA.
    pub rrtype: u8,
    pub ttl: u32,
    /// The raw address bytes; empty for a record packed without rdata.
    pub address: Vec<u8>,
}

/// Everything the engine used to read off the unpacked upstream response.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Extracted {
    /// Header rcode, including the EDNS extended bits.
    pub rcode: u16,
    /// Every A/AAAA answer is null or loopback.
    pub blocked: bool,
    /// `dns.Question[0].Name` of the response, raw (trailing dot kept).
    pub question_name: String,
    /// A/AAAA answers in record order, with their TTLs.
    pub addresses: Vec<AddressRecord>,
    /// CNAME/SVCB/HTTPS targets, normalized exactly like Go did.
    pub chain_targets: Vec<ChainTarget>,
    /// Unique address texts in answer order.
    pub ips: Vec<String>,
    /// `strings.Join(ips, ",")`.
    pub resolved_ips: String,
}

struct Sections {
    header: MessageHeader,
    questions: Vec<Question>,
    rcode: u16,
}

/// `parseDNSQuery`: unpacks the query and reports its first question.
pub fn query_info(query: &[u8]) -> QueryInfo {
    let Some(sections) = parse_sections(query) else {
        return QueryInfo::invalid();
    };
    if sections.header.is_response() || sections.questions.is_empty() {
        return QueryInfo::invalid();
    }
    let name = sections.questions[0].name.to_ascii_lowercase();
    QueryInfo {
        name: name.strip_suffix('.').unwrap_or(&name).to_string(),
        qtype: sections.questions[0].qtype,
        valid: true,
    }
}

/// `validateDNSResponseParsed`: checks one response against the query it answers.
pub fn validate(query: &[u8], response: &[u8]) -> Validation {
    let Some(parsed) = parse_sections(query) else {
        return Validation {
            status: status::INVALID_QUERY,
            rcode: 0,
        };
    };
    if parsed.header.is_response() || parsed.questions.is_empty() {
        return Validation {
            status: status::INVALID_QUERY_FLAGS,
            rcode: 0,
        };
    }
    let Some(reply) = parse_sections(response) else {
        return Validation {
            status: status::INVALID_RESPONSE,
            rcode: 0,
        };
    };
    if !reply.header.is_response() || reply.header.id != parsed.header.id {
        return Validation {
            status: status::TRANSACTION_MISMATCH,
            rcode: 0,
        };
    }
    if reply.questions.len() != parsed.questions.len() {
        return Validation {
            status: status::QUESTION_COUNT,
            rcode: 0,
        };
    }
    for (expected, actual) in parsed.questions.iter().zip(reply.questions.iter()) {
        if !expected.name.eq_ignore_ascii_case(&actual.name)
            || expected.qtype != actual.qtype
            || expected.qclass != actual.qclass
        {
            return Validation {
                status: status::QUESTION_MISMATCH,
                rcode: 0,
            };
        }
    }
    // NXDOMAIN is a valid negative answer; every other non-NOERROR code is a provider failure.
    match reply.rcode {
        0 | 3 => Validation {
            status: status::ACCEPTED,
            rcode: 0,
        },
        rcode => Validation {
            status: status::UPSTREAM_RCODE,
            rcode,
        },
    }
}

/// Walks one response and returns everything the engine logs and grants from it.
///
/// `None` means `dns.Msg.Unpack` would have failed (short header, broken name, truncated record,
/// or an A/AAAA whose rdata length is not 4/16). Answer sections may stop on a record boundary
/// with records still declared, exactly like the Go unpacker.
pub fn extract(response: &[u8]) -> Option<Extracted> {
    let header = parse_header(response)?;
    let mut extracted = Extracted {
        rcode: (header.flags & 0xf) as u16,
        ..Extracted::default()
    };
    let mut offset = 12usize;
    if offset == response.len() {
        return Some(extracted);
    }
    for _ in 0..header.question_count {
        let (question, next) = parse_question(response, offset, false)?;
        offset = next;
        if extracted.question_name.is_empty() {
            extracted.question_name = question.name;
        }
    }

    let answer_end = header.answer_count as usize + header.authority_count as usize;
    let total = answer_end + header.additional_count as usize;
    let mut owned: Vec<(u8, Vec<u8>)> = Vec::with_capacity(header.answer_count as usize);
    let mut ext_rcode: Option<u16> = None;

    for index in 0..total {
        if offset == response.len() {
            break;
        }
        let (_, cursor) = unpack_name(response, offset, response.len())?;
        if cursor + 10 > response.len() {
            return None;
        }
        let rrtype = read_u16(response, cursor)?;
        let ttl = read_u32(response, cursor + 4)?;
        let rd_length = read_u16(response, cursor + 8)? as usize;
        let rdata = cursor + 10;
        let end = rdata + rd_length;
        if end > response.len() {
            return None;
        }

        if index >= answer_end {
            if rrtype == TYPE_OPT && ext_rcode.is_none() {
                ext_rcode = Some((ttl >> 24) as u16);
            }
            offset = end;
            continue;
        }

        if rd_length == 0 {
            // `noRdata` in miekg/dns: the record exists without a body. An A/AAAA without an
            // address still counts as an address record and prints as `<nil>`.
            match rrtype {
                TYPE_A => {
                    extracted.addresses.push(AddressRecord {
                        rrtype: TYPE_A_BYTE,
                        ttl,
                        address: Vec::new(),
                    });
                    owned.push((TYPE_A_BYTE, Vec::new()));
                }
                TYPE_AAAA => {
                    extracted.addresses.push(AddressRecord {
                        rrtype: TYPE_AAAA_BYTE,
                        ttl,
                        address: Vec::new(),
                    });
                    owned.push((TYPE_AAAA_BYTE, Vec::new()));
                }
                _ => {}
            }
            offset = end;
            continue;
        }

        match rrtype {
            TYPE_A => {
                if rd_length != 4 {
                    return None;
                }
                let address = response[rdata..end].to_vec();
                extracted.addresses.push(AddressRecord {
                    rrtype: TYPE_A_BYTE,
                    ttl,
                    address: address.clone(),
                });
                owned.push((TYPE_A_BYTE, address));
            }
            TYPE_AAAA => {
                if rd_length != 16 {
                    return None;
                }
                let address = response[rdata..end].to_vec();
                extracted.addresses.push(AddressRecord {
                    rrtype: TYPE_AAAA_BYTE,
                    ttl,
                    address: address.clone(),
                });
                owned.push((TYPE_AAAA_BYTE, address));
            }
            TYPE_CNAME => {
                let (name, consumed) = unpack_name(response, rdata, end)?;
                if consumed != end {
                    return None;
                }
                push_chain_target(&mut extracted.chain_targets, &name, ChainKind::Cname);
            }
            TYPE_SVCB | TYPE_HTTPS => {
                if rd_length < 2 {
                    return None;
                }
                if rd_length > 2 {
                    let (name, consumed) = unpack_name(response, rdata + 2, end)?;
                    if consumed > end {
                        return None;
                    }
                    push_chain_target(&mut extracted.chain_targets, &name, ChainKind::Svcb);
                }
            }
            _ => {}
        }
        offset = end;
    }

    if let Some(extended) = ext_rcode {
        extracted.rcode |= extended << 4;
    }

    let entries: Vec<AnswerEntry<'_>> = owned
        .iter()
        .map(|(rrtype, address)| AnswerEntry {
            rrtype: *rrtype,
            address,
        })
        .collect();
    let inspection = answer::inspect(&entries);
    extracted.blocked = inspection.blocked;
    extracted.resolved_ips = inspection.addresses;
    if !extracted.resolved_ips.is_empty() {
        extracted.ips = extracted
            .resolved_ips
            .split(',')
            .map(str::to_string)
            .collect();
    }
    Some(extracted)
}

fn push_chain_target(targets: &mut Vec<ChainTarget>, name: &str, kind: ChainKind) {
    let trimmed = name.trim_matches(is_go_space);
    let lowered = trimmed.to_ascii_lowercase();
    let domain = lowered.strip_suffix('.').unwrap_or(&lowered);
    if domain.is_empty() {
        return;
    }
    targets.push(ChainTarget {
        domain: domain.to_string(),
        kind,
    });
}

/// The ASCII half of Go's `unicode.IsSpace`.
fn is_go_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\n' | '\x0b' | '\x0c' | '\r')
}

/// Mirrors `dns.Msg.Unpack`: header, questions (lenient) and a record walk that only reads what
/// it needs. The answer payloads are not decoded here; [`extract`] does that.
fn parse_sections(wire: &[u8]) -> Option<Sections> {
    let header = parse_header(wire)?;
    let mut sections = Sections {
        header,
        questions: Vec::with_capacity(header.question_count as usize),
        rcode: (header.flags & 0xf) as u16,
    };
    let mut offset = 12usize;
    if offset == wire.len() {
        return Some(sections);
    }
    for _ in 0..header.question_count {
        let (question, next) = parse_question(wire, offset, false)?;
        if next == offset {
            return None;
        }
        offset = next;
        sections.questions.push(question);
    }

    let answer_end = header.answer_count as usize + header.authority_count as usize;
    let total = answer_end + header.additional_count as usize;
    let mut ext_rcode: Option<u16> = None;
    for index in 0..total {
        if offset == wire.len() {
            break;
        }
        let (_, cursor) = unpack_name(wire, offset, wire.len())?;
        if cursor + 10 > wire.len() {
            return None;
        }
        let rrtype = read_u16(wire, cursor)?;
        let ttl = read_u32(wire, cursor + 4)?;
        let rd_length = read_u16(wire, cursor + 8)? as usize;
        let rdata = cursor + 10;
        let end = rdata + rd_length;
        if end > wire.len() {
            return None;
        }
        if index >= answer_end && rrtype == TYPE_OPT && ext_rcode.is_none() {
            ext_rcode = Some((ttl >> 24) as u16);
        }
        offset = end;
    }
    if let Some(extended) = ext_rcode {
        sections.rcode |= extended << 4;
    }
    Some(sections)
}

#[cfg(test)]
mod tests;

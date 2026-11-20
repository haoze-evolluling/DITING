use diting_dns_wire::{
    parse_header, parse_question, read_u16, read_u32, unpack_name, ChainKind, ChainTarget,
    MessageHeader, Question,
};

use crate::answer::{self, AnswerEntry};

pub const TYPE_A: u16 = 1;
pub const TYPE_CNAME: u16 = 5;
pub const TYPE_AAAA: u16 = 28;
pub const TYPE_OPT: u16 = 41;
pub const TYPE_SVCB: u16 = 64;
pub const TYPE_HTTPS: u16 = 65;

const TYPE_A_BYTE: u8 = 1;
const TYPE_AAAA_BYTE: u8 = 28;

pub mod status {
    pub const ACCEPTED: u8 = 0;
    pub const UPSTREAM_RCODE: u8 = 1;
    pub const INVALID_QUERY: u8 = 2;
    pub const INVALID_QUERY_FLAGS: u8 = 3;
    pub const INVALID_RESPONSE: u8 = 4;
    pub const TRANSACTION_MISMATCH: u8 = 5;
    pub const QUESTION_COUNT: u8 = 6;
    pub const QUESTION_MISMATCH: u8 = 7;
}

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Validation {
    pub status: u8,
    pub rcode: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AddressRecord {
    pub rrtype: u8,
    pub ttl: u32,
    pub address: Vec<u8>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Extracted {
    pub rcode: u16,
    pub blocked: bool,
    pub question_name: String,
    pub addresses: Vec<AddressRecord>,
    pub chain_targets: Vec<ChainTarget>,
    pub ips: Vec<String>,
    pub resolved_ips: String,
}

struct Sections {
    header: MessageHeader,
    questions: Vec<Question>,
    rcode: u16,
}

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

fn is_go_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\n' | '\x0b' | '\x0c' | '\r')
}

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

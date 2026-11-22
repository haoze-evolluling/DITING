use diting_dns_wire::{pack_name, parse_answer_records, parse_header, parse_question};
use diting_go_compat::ip::to4;
use diting_go_compat::netaddr::parse_ip;

pub const TYPE_A: u16 = 1;
pub const TYPE_CNAME: u16 = 5;
pub const TYPE_AAAA: u16 = 28;
pub const CLASS_INET: u16 = 1;

pub const RCODE_SUCCESS: u16 = 0;
pub const RCODE_SERVFAIL: u16 = 2;
pub const RCODE_NXDOMAIN: u16 = 3;
pub const RCODE_REFUSED: u16 = 5;

pub const REWRITE_ANSWER_TTL: u32 = 300;
pub const LOCAL_ASSET_IPV4: [u8; 4] = [198, 51, 100, 1];

pub const PLAN_OK: u8 = 0;
pub const PLAN_NOT_APPLICABLE: u8 = 1;

pub const RESPONSE_CUSTOM_IP: u8 = 0;
pub const RESPONSE_NXDOMAIN: u8 = 1;
pub const RESPONSE_REFUSED: u8 = 2;
pub const RESPONSE_NO_DATA: u8 = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplyRecord {
    pub rrtype: u16,
    pub class: u16,
    pub ttl: u32,
    pub name: String,
    pub rdata: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplyPlan {
    pub status: u8,
    pub rcode: u16,
    pub recursion_available: bool,
    pub answers: Vec<ReplyRecord>,
}

impl ReplyPlan {
    fn empty(rcode: u16, recursion_available: bool) -> Self {
        ReplyPlan {
            status: PLAN_OK,
            rcode,
            recursion_available,
            answers: Vec::new(),
        }
    }

    fn with(rcode: u16, recursion_available: bool, answers: Vec<ReplyRecord>) -> Self {
        ReplyPlan {
            status: PLAN_OK,
            rcode,
            recursion_available,
            answers,
        }
    }

    fn not_applicable() -> Self {
        ReplyPlan {
            status: PLAN_NOT_APPLICABLE,
            rcode: RCODE_SUCCESS,
            recursion_available: false,
            answers: Vec::new(),
        }
    }

    pub fn is_not_applicable(&self) -> bool {
        self.status == PLAN_NOT_APPLICABLE
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Query {
    pub name: String,
    pub qtype: u16,
    pub qclass: u16,
}

pub fn parse_query(wire: &[u8]) -> Option<Query> {
    let header = parse_header(wire)?;
    if header.question_count == 0 {
        return None;
    }
    let (question, _) = parse_question(wire, 12, true)?;
    Some(Query {
        name: question.name,
        qtype: question.qtype,
        qclass: question.qclass,
    })
}

fn address_record(query: &Query, rrtype: u16, rdata: Vec<u8>) -> ReplyRecord {
    ReplyRecord {
        rrtype,
        class: CLASS_INET,
        ttl: REWRITE_ANSWER_TTL,
        name: query.name.clone(),
        rdata,
    }
}

pub fn block(query_wire: &[u8], mode: u8) -> Option<ReplyPlan> {
    let query = parse_query(query_wire)?;
    let plan = match mode {
        RESPONSE_NXDOMAIN => ReplyPlan::empty(RCODE_NXDOMAIN, false),
        RESPONSE_REFUSED => ReplyPlan::empty(RCODE_REFUSED, false),
        RESPONSE_NO_DATA => ReplyPlan::empty(RCODE_SUCCESS, false),
        _ => {
            let mut answers = Vec::new();
            if query.qtype == TYPE_A {
                answers.push(address_record(&query, TYPE_A, vec![0, 0, 0, 0]));
            } else if query.qtype == TYPE_AAAA {
                answers.push(address_record(&query, TYPE_AAAA, vec![0u8; 16]));
            }
            ReplyPlan::with(RCODE_SUCCESS, false, answers)
        }
    };
    Some(plan)
}

pub fn local_asset(query_wire: &[u8]) -> Option<ReplyPlan> {
    let query = parse_query(query_wire)?;
    let answers = if query.qtype == TYPE_A {
        vec![address_record(&query, TYPE_A, LOCAL_ASSET_IPV4.to_vec())]
    } else {
        Vec::new()
    };
    Some(ReplyPlan::with(RCODE_SUCCESS, false, answers))
}

pub fn ddr(query_wire: &[u8]) -> Option<ReplyPlan> {
    parse_query(query_wire)?;
    Some(ReplyPlan::empty(RCODE_NXDOMAIN, false))
}

pub fn servfail(query_wire: &[u8]) -> Option<ReplyPlan> {
    parse_query(query_wire)?;
    Some(ReplyPlan::empty(RCODE_SERVFAIL, false))
}

pub fn rewrite_ip(query_wire: &[u8], ip: &str) -> Option<ReplyPlan> {
    let query = parse_query(query_wire)?;
    let rdata = if query.qtype == TYPE_AAAA {
        parse_ip(ip)?.to_vec()
    } else if query.qtype == TYPE_A {
        to4(&parse_ip(ip)?)?.to_vec()
    } else {
        return Some(ReplyPlan::with(RCODE_SUCCESS, true, Vec::new()));
    };
    Some(ReplyPlan::with(
        RCODE_SUCCESS,
        true,
        vec![address_record(&query, query.qtype, rdata)],
    ))
}

pub fn rewrite_cname(query_wire: &[u8], target: &str, resolved_wire: &[u8]) -> Option<ReplyPlan> {
    let query = parse_query(query_wire)?;
    let Some(records) = parse_answer_records(resolved_wire) else {
        return Some(ReplyPlan::not_applicable());
    };

    let mut answers = Vec::with_capacity(records.len() + 1);
    answers.push(ReplyRecord {
        rrtype: TYPE_CNAME,
        class: CLASS_INET,
        ttl: REWRITE_ANSWER_TTL,
        name: query.name.clone(),
        rdata: fqdn(target).into_bytes(),
    });

    for record in records {
        let wanted = match query.qtype {
            TYPE_A => record.rrtype == TYPE_A && record.rdata.len() == 4,
            TYPE_AAAA => record.rrtype == TYPE_AAAA && record.rdata.len() == 16,
            _ => false,
        };
        if wanted {
            answers.push(ReplyRecord {
                rrtype: record.rrtype,
                class: record.class,
                ttl: record.ttl,
                name: record.name,
                rdata: record.rdata,
            });
        }
    }

    if answers.len() == 1 {
        return Some(ReplyPlan::not_applicable());
    }
    Some(ReplyPlan::with(RCODE_SUCCESS, false, answers))
}

fn fqdn(name: &str) -> String {
    if name.ends_with('.') {
        name.to_string()
    } else {
        format!("{name}.")
    }
}

#[cfg(test)]
mod tests;

pub fn render(query_wire: &[u8], plan: &ReplyPlan) -> Option<Vec<u8>> {
    if plan.status != PLAN_OK {
        return None;
    }
    let header = parse_header(query_wire)?;
    let (_, question_end) = parse_question(query_wire, 12, true)?;
    if header.question_count == 0 {
        return None;
    }

    let mut out = Vec::with_capacity(512);
    out.extend_from_slice(&header.id.to_be_bytes());
    let opcode = header.flags & 0x7800;
    let recursion_desired = header.flags & 0x0100;
    let recursion_available = if plan.recursion_available { 0x0080 } else { 0 };
    let flags = 0x8000 | opcode | recursion_desired | recursion_available | (plan.rcode & 0x000f);
    out.extend_from_slice(&flags.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out.extend_from_slice(&(plan.answers.len() as u16).to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&0u16.to_be_bytes());
    out.extend_from_slice(&query_wire[12..question_end]);

    for record in &plan.answers {
        if !pack_name(&record.name, &mut out) {
            return None;
        }
        out.extend_from_slice(&record.rrtype.to_be_bytes());
        out.extend_from_slice(&record.class.to_be_bytes());
        out.extend_from_slice(&record.ttl.to_be_bytes());
        let length_at = out.len();
        out.extend_from_slice(&[0, 0]);

        let start = out.len();
        match record.rrtype {
            TYPE_A | TYPE_AAAA => out.extend_from_slice(&record.rdata),
            TYPE_CNAME => {
                let target = std::str::from_utf8(&record.rdata).ok()?;
                if !pack_name(target, &mut out) {
                    return None;
                }
            }
            _ => return None,
        }
        let length = out.len() - start;
        let length = u16::try_from(length).ok()?;
        out[length_at..length_at + 2].copy_from_slice(&length.to_be_bytes());
    }

    Some(out)
}

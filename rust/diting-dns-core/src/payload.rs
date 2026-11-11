//! The binary layouts shared with `android/engine/dns_core_payload.go`.
//!
//! Query info (kernel -> Go):
//!
//! ```text
//! | u8 layout | u8 valid | u16 qtype | u16 name_len | bytes name |
//! ```
//!
//! Validation (kernel -> Go):
//!
//! ```text
//! | u8 layout | u8 status | u16 rcode |
//! ```
//!
//! Answer extraction (kernel -> Go):
//!
//! ```text
//! | u8 layout | u16 rcode | u8 flags | u16 question_len | bytes question
//! | u16 address_count | count × ( u8 rrtype | u32 ttl | u16 len | bytes address )
//! | u16 chain_count   | count × ( u8 kind | u16 len | bytes domain )
//! | u16 ip_count      | count × ( u16 len | bytes ip )
//! | u16 resolved_len  | bytes resolved_ips |
//! ```
//!
//! `flags` bit 0 is "blocked". Every frame pins the same layout; a drifted version byte, a length
//! that disagrees with the payload or trailing bytes are hard errors, never a misread.

use crate::message::Extracted;

/// Layout of every frame in this file; must match `dnsCorePayloadLayoutVersion` in Go.
pub const LAYOUT_VERSION: u8 = 1;

/// The answer is a null block (`isUpstreamBlockedMsg`).
pub const FLAG_BLOCKED: u8 = 1 << 0;
/// The reply advertises recursion availability (`dns.Msg.RecursionAvailable`).
pub const FLAG_RECURSION_AVAILABLE: u8 = 1 << 0;

const QUERY_HEADER: usize = 1 + 1 + 2 + 2;
const VALIDATION_LEN: usize = 1 + 1 + 2;
const EXTRACT_HEADER: usize = 1 + 2 + 1;

/// Encodes the `parseDNSQuery` result.
pub fn encode_query_info(valid: bool, name: &str, qtype: u16) -> Vec<u8> {
    let text = name.as_bytes();
    let mut out = Vec::with_capacity(QUERY_HEADER + text.len());
    out.push(LAYOUT_VERSION);
    out.push(u8::from(valid));
    out.extend_from_slice(&qtype.to_le_bytes());
    out.extend_from_slice(&(text.len() as u16).to_le_bytes());
    out.extend_from_slice(text);
    out
}

/// Reads the query info payload.
pub fn decode_query_info(payload: &[u8]) -> Option<(bool, String, u16)> {
    if payload.len() < QUERY_HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let valid = match payload[1] {
        0 => false,
        1 => true,
        _ => return None,
    };
    let qtype = u16::from_le_bytes(payload[2..4].try_into().ok()?);
    let length = u16::from_le_bytes(payload[4..6].try_into().ok()?) as usize;
    if payload.len() - QUERY_HEADER != length {
        return None;
    }
    let name = std::str::from_utf8(&payload[QUERY_HEADER..]).ok()?;
    Some((valid, name.to_string(), qtype))
}

/// Encodes one validation outcome.
pub fn encode_validation(status: u8, rcode: u16) -> Vec<u8> {
    let mut out = Vec::with_capacity(VALIDATION_LEN);
    out.push(LAYOUT_VERSION);
    out.push(status);
    out.extend_from_slice(&rcode.to_le_bytes());
    out
}

/// Reads one validation outcome.
pub fn decode_validation(payload: &[u8]) -> Option<(u8, u16)> {
    if payload.len() != VALIDATION_LEN || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let rcode = u16::from_le_bytes(payload[2..4].try_into().ok()?);
    Some((payload[1], rcode))
}

/// Encodes one extracted answer.
pub fn encode_extracted(extracted: &Extracted) -> Vec<u8> {
    let question = extracted.question_name.as_bytes();
    let mut out = Vec::with_capacity(
        EXTRACT_HEADER
            + 2
            + question.len()
            + 2
            + extracted.addresses.len() * (1 + 4 + 2)
            + 2
            + extracted.chain_targets.len() * 3
            + 2
            + extracted.ips.len() * 2
            + 2
            + extracted.resolved_ips.len(),
    );
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&extracted.rcode.to_le_bytes());
    out.push(if extracted.blocked { FLAG_BLOCKED } else { 0 });
    push_text(&mut out, question);

    out.extend_from_slice(&(extracted.addresses.len() as u16).to_le_bytes());
    for record in &extracted.addresses {
        out.push(record.rrtype);
        out.extend_from_slice(&record.ttl.to_le_bytes());
        push_text(&mut out, &record.address);
    }

    out.extend_from_slice(&(extracted.chain_targets.len() as u16).to_le_bytes());
    for target in &extracted.chain_targets {
        out.push(target.kind.code());
        push_text(&mut out, target.domain.as_bytes());
    }

    out.extend_from_slice(&(extracted.ips.len() as u16).to_le_bytes());
    for ip in &extracted.ips {
        push_text(&mut out, ip.as_bytes());
    }

    push_text(&mut out, extracted.resolved_ips.as_bytes());
    out
}

/// Reads one extracted answer (used by the Rust tests and the FFI round trip).
pub fn decode_extracted(payload: &[u8]) -> Option<Extracted> {
    let mut reader = Reader::new(payload);
    reader.expect_layout()?;
    let rcode = reader.u16()?;
    let flags = reader.u8()?;
    if flags & !FLAG_BLOCKED != 0 {
        return None;
    }
    let question_name = reader.text()?;
    let address_count = reader.u16()? as usize;
    let mut addresses = Vec::with_capacity(address_count);
    for _ in 0..address_count {
        let rrtype = reader.u8()?;
        if rrtype != 1 && rrtype != 28 {
            return None;
        }
        let ttl = reader.u32()?;
        let address = reader.bytes()?;
        addresses.push(crate::message::AddressRecord {
            rrtype,
            ttl,
            address,
        });
    }
    let chain_count = reader.u16()? as usize;
    let mut chain_targets = Vec::with_capacity(chain_count);
    for _ in 0..chain_count {
        let kind = reader.u8()?;
        let domain = reader.text()?;
        chain_targets.push(diting_dns_wire::ChainTarget {
            domain,
            kind: diting_dns_wire::ChainKind::from_code(kind)?,
        });
    }
    let ip_count = reader.u16()? as usize;
    let mut ips = Vec::with_capacity(ip_count);
    for _ in 0..ip_count {
        ips.push(reader.text()?);
    }
    let resolved_ips = reader.text()?;
    if !reader.done() {
        return None;
    }
    Some(Extracted {
        rcode,
        blocked: flags & FLAG_BLOCKED != 0,
        question_name,
        addresses,
        chain_targets,
        ips,
        resolved_ips,
    })
}

fn push_text(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u16).to_le_bytes());
    out.extend_from_slice(bytes);
}

/// Encodes one reply plan (kernel -> Go).
///
/// ```text
/// | u8 layout | u8 status | u16 rcode | u8 flags | u16 answer_count |
///   count × ( u16 rrtype | u16 class | u32 ttl | u16 name_len | bytes name
///           | u16 rdata_len | bytes rdata )
/// ```
pub fn encode_reply(plan: &crate::reply::ReplyPlan) -> Vec<u8> {
    let mut out = Vec::with_capacity(6 + plan.answers.len() * 12);
    out.push(LAYOUT_VERSION);
    out.push(plan.status);
    out.extend_from_slice(&plan.rcode.to_le_bytes());
    out.push(if plan.recursion_available {
        FLAG_RECURSION_AVAILABLE
    } else {
        0
    });
    out.extend_from_slice(&(plan.answers.len() as u16).to_le_bytes());
    for answer in &plan.answers {
        out.extend_from_slice(&answer.rrtype.to_le_bytes());
        out.extend_from_slice(&answer.class.to_le_bytes());
        out.extend_from_slice(&answer.ttl.to_le_bytes());
        push_text(&mut out, answer.name.as_bytes());
        push_text(&mut out, &answer.rdata);
    }
    out
}

/// Reads one reply plan (used by the Rust tests and the FFI round trip).
pub fn decode_reply(payload: &[u8]) -> Option<crate::reply::ReplyPlan> {
    let mut reader = Reader::new(payload);
    reader.expect_layout()?;
    let status = reader.u8()?;
    if status > crate::reply::PLAN_NOT_APPLICABLE {
        return None;
    }
    let rcode = reader.u16()?;
    let flags = reader.u8()?;
    if flags & !FLAG_RECURSION_AVAILABLE != 0 {
        return None;
    }
    let answer_count = reader.u16()? as usize;
    let mut answers = Vec::with_capacity(answer_count);
    for _ in 0..answer_count {
        let rrtype = reader.u16()?;
        let class = reader.u16()?;
        let ttl = reader.u32()?;
        let name = reader.text()?;
        let rdata = reader.bytes()?;
        answers.push(crate::reply::ReplyRecord {
            rrtype,
            class,
            ttl,
            name,
            rdata,
        });
    }
    if !reader.done() {
        return None;
    }
    Some(crate::reply::ReplyPlan {
        status,
        rcode,
        recursion_available: flags & FLAG_RECURSION_AVAILABLE != 0,
        answers,
    })
}

/// Encodes one rewrite lookup result (kernel -> Go).
pub fn encode_lookup(entry: Option<&diting_config_core::rewrite::Entry>) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION, u8::from(entry.is_some())];
    if let Some(entry) = entry {
        push_text(&mut out, entry.cname.as_bytes());
        push_text(&mut out, entry.ip4.as_bytes());
        push_text(&mut out, entry.ip6.as_bytes());
    }
    out
}

/// The three normalized fields of one rewrite lookup.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LookupResult {
    pub cname: String,
    pub ip4: String,
    pub ip6: String,
}

/// Reads one rewrite lookup result.
pub fn decode_lookup(payload: &[u8]) -> Option<Option<LookupResult>> {
    let mut reader = Reader::new(payload);
    reader.expect_layout()?;
    match reader.u8()? {
        0 => {
            if reader.done() {
                Some(None)
            } else {
                None
            }
        }
        1 => {
            let result = LookupResult {
                cname: reader.text()?,
                ip4: reader.text()?,
                ip6: reader.text()?,
            };
            if reader.done() {
                Some(Some(result))
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Encodes the `(domain, targets)` pairs Go sends when a rule set is pushed.
pub fn encode_rewrite_entries(entries: &[(String, Vec<String>)]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
    for (domain, targets) in entries {
        push_text(&mut out, domain.as_bytes());
        out.extend_from_slice(&(targets.len() as u16).to_le_bytes());
        for target in targets {
            push_text(&mut out, target.as_bytes());
        }
    }
    out
}

/// Reads the rewrite-rule payload Go sends.
pub fn decode_rewrite_entries(payload: &[u8]) -> Option<Vec<(String, Vec<String>)>> {
    let mut reader = Reader::new(payload);
    reader.expect_layout()?;
    let count = reader.u32()? as usize;
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let domain = reader.text()?;
        let target_count = reader.u16()? as usize;
        let mut targets = Vec::with_capacity(target_count);
        for _ in 0..target_count {
            targets.push(reader.text()?);
        }
        entries.push((domain, targets));
    }
    if reader.done() {
        Some(entries)
    } else {
        None
    }
}

struct Reader<'a> {
    data: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Reader { data, offset: 0 }
    }

    fn expect_layout(&mut self) -> Option<()> {
        if self.u8()? != LAYOUT_VERSION {
            return None;
        }
        Some(())
    }

    fn u8(&mut self) -> Option<u8> {
        let byte = *self.data.get(self.offset)?;
        self.offset += 1;
        Some(byte)
    }

    fn u16(&mut self) -> Option<u16> {
        let bytes = self.data.get(self.offset..self.offset + 2)?;
        self.offset += 2;
        Some(u16::from_le_bytes([bytes[0], bytes[1]]))
    }

    fn u32(&mut self) -> Option<u32> {
        let bytes = self.data.get(self.offset..self.offset + 4)?;
        self.offset += 4;
        Some(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn bytes(&mut self) -> Option<Vec<u8>> {
        let length = self.u16()? as usize;
        let bytes = self.data.get(self.offset..self.offset + length)?;
        self.offset += length;
        Some(bytes.to_vec())
    }

    fn text(&mut self) -> Option<String> {
        String::from_utf8(self.bytes()?).ok()
    }

    fn done(&self) -> bool {
        self.offset == self.data.len()
    }
}

#[cfg(test)]
mod tests;

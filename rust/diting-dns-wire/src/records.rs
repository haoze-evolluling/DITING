//! Answer-record walk with owner names and raw rdata.
//!
//! The reply builder needs more than [`crate::parse_response`] exposes: the A/AAAA records it
//! copies out of a rewritten answer keep their own owner name, class, TTL and rdata. This walk
//! returns exactly those fields, decoded with the same presentation escaping the rest of the wire
//! layer uses (`unpack_name`), so Go can fill a `dns.RR` without re-parsing the message.

use crate::bits::{read_u16, read_u32};
use crate::name::unpack_name;

/// One answer-section record.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Record {
    /// `dns.RR_Header.Name`, already escaped for presentation.
    pub name: String,
    /// `dns.RR_Header.Rrtype`.
    pub rrtype: u16,
    /// `dns.RR_Header.Class`.
    pub class: u16,
    /// `dns.RR_Header.Ttl`.
    pub ttl: u32,
    /// The record body exactly as it appears on the wire (A/AAAA: the address bytes).
    pub rdata: Vec<u8>,
}

/// Reads the answer section of one message.
///
/// Like the cache walk, a message that ends exactly on a record boundary is accepted with the
/// records the header declared but did not carry dropped; that is the only leniency
/// `dns.Msg.Unpack` had here.
pub fn parse_answer_records(wire: &[u8]) -> Option<Vec<Record>> {
    if wire.len() < 12 {
        return None;
    }
    let question_count = read_u16(wire, 4)? as usize;
    let answer_count = read_u16(wire, 6)? as usize;

    let mut offset = 12usize;
    for _ in 0..question_count {
        let (_, next) = unpack_name(wire, offset, wire.len())?;
        if next + 4 > wire.len() {
            return None;
        }
        offset = next + 4;
    }

    let mut records = Vec::new();
    for _ in 0..answer_count {
        if offset == wire.len() {
            break;
        }
        let (name, next) = unpack_name(wire, offset, wire.len())?;
        if next + 10 > wire.len() {
            return None;
        }
        let rrtype = read_u16(wire, next)?;
        let class = read_u16(wire, next + 2)?;
        let ttl = read_u32(wire, next + 4)?;
        let rd_length = read_u16(wire, next + 8)? as usize;
        let rdata = next + 10;
        let end = rdata + rd_length;
        if end > wire.len() {
            return None;
        }
        records.push(Record {
            name,
            rrtype,
            class,
            ttl,
            rdata: wire[rdata..end].to_vec(),
        });
        offset = end;
    }
    Some(records)
}

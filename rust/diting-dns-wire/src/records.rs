use crate::bits::{read_u16, read_u32};
use crate::name::{skip_name, unpack_name};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Record {
    pub name: String,
    pub rrtype: u16,
    pub class: u16,
    pub ttl: u32,
    pub rdata: Vec<u8>,
}

pub fn parse_answer_records(wire: &[u8]) -> Option<Vec<Record>> {
    if wire.len() < 12 {
        return None;
    }
    let question_count = read_u16(wire, 4)? as usize;
    let answer_count = read_u16(wire, 6)? as usize;

    let mut offset = 12usize;
    for _ in 0..question_count {
        let next = skip_name(wire, offset, wire.len())?;
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

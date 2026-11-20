use crate::bits::{read_u16, read_u32};
use crate::name::unpack_name;

const TYPE_A: u16 = 1;
const TYPE_CNAME: u16 = 5;
const TYPE_SOA: u16 = 6;
const TYPE_AAAA: u16 = 28;
const TYPE_OPT: u16 = 41;
const TYPE_SVCB: u16 = 64;
const TYPE_HTTPS: u16 = 65;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChainKind {
    Cname,
    Svcb,
}

impl ChainKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ChainKind::Cname => "cname",
            ChainKind::Svcb => "svcb",
        }
    }

    pub fn code(self) -> u8 {
        match self {
            ChainKind::Cname => 0,
            ChainKind::Svcb => 1,
        }
    }

    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            0 => Some(ChainKind::Cname),
            1 => Some(ChainKind::Svcb),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChainTarget {
    pub domain: String,
    pub kind: ChainKind,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ResponseMeta {
    pub truncated: bool,
    pub rcode: u8,
    pub answer_count: u16,
    pub min_ttl: Option<u32>,
    pub answer_ttl_offsets: Vec<u16>,
    pub authority_ttl_offsets: Vec<u16>,
    pub chain_targets: Vec<ChainTarget>,
    pub ips: Vec<String>,
    pub resolved_ips: String,
}

pub fn parse_response(wire: &[u8]) -> Option<ResponseMeta> {
    if wire.len() < 12 {
        return None;
    }
    let flags = read_u16(wire, 2)?;
    let question_count = read_u16(wire, 4)? as usize;
    let answer_count = read_u16(wire, 6)? as usize;
    let authority_count = read_u16(wire, 8)? as usize;
    let additional_count = read_u16(wire, 10)? as usize;

    let mut offset = 12usize;
    for _ in 0..question_count {
        let (_, next) = unpack_name(wire, offset, wire.len())?;
        if next + 4 > wire.len() {
            return None;
        }
        offset = next + 4;
    }

    let mut meta = ResponseMeta {
        truncated: flags & 0x0200 != 0,
        rcode: (flags & 0x000f) as u8,
        ..ResponseMeta::default()
    };
    let mut first_soa: Option<(u32, u32)> = None;
    let mut parsed_answers = 0usize;

    for index in 0..answer_count + authority_count + additional_count {
        if offset == wire.len() {
            break;
        }
        let (_, header) = unpack_name(wire, offset, wire.len())?;
        if header + 10 > wire.len() {
            return None;
        }
        let rrtype = read_u16(wire, header)?;
        let ttl = read_u32(wire, header + 4)?;
        let rd_length = read_u16(wire, header + 8)? as usize;
        let rdata = header + 10;
        let rdata_end = rdata + rd_length;
        if rdata_end > wire.len() {
            return None;
        }

        if index < answer_count {
            parse_answer(wire, rrtype, ttl, rd_length, header, rdata_end, &mut meta)?;
            parsed_answers += 1;
        } else if index < answer_count + authority_count {
            if rrtype != TYPE_OPT && parsed_answers == 0 {
                meta.authority_ttl_offsets.push(to_offset(header + 4)?);
            }
            if rrtype == TYPE_SOA && first_soa.is_none() {
                first_soa = Some(parse_soa(wire, ttl, rd_length, rdata, rdata_end)?);
            }
        }
        offset = rdata_end;
    }
    meta.answer_count = parsed_answers as u16;

    if meta.min_ttl.is_none() {
        if let Some((soa_ttl, minttl)) = first_soa {
            let mut ttl = minttl;
            if ttl == 0 || (soa_ttl > 0 && soa_ttl < ttl) {
                ttl = soa_ttl;
            }
            meta.min_ttl = Some(ttl);
        }
    }

    meta.resolved_ips = meta.ips.join(",");
    Some(meta)
}

pub fn patch_response(wire: &[u8], offsets: &[u16], query_id: u16, ttl: u32) -> Option<Vec<u8>> {
    let mut patched = vec![0u8; wire.len()];
    if patch_response_into(wire, offsets, query_id, ttl, &mut patched) {
        Some(patched)
    } else {
        None
    }
}

pub fn patch_response_into(
    wire: &[u8],
    offsets: &[u16],
    query_id: u16,
    ttl: u32,
    out: &mut [u8],
) -> bool {
    if wire.len() < 12 || out.len() < wire.len() {
        return false;
    }
    out[..wire.len()].copy_from_slice(wire);
    out[0..2].copy_from_slice(&query_id.to_be_bytes());
    for &offset in offsets {
        let start = offset as usize;
        if start + 4 <= wire.len() {
            out[start..start + 4].copy_from_slice(&ttl.to_be_bytes());
        }
    }
    true
}

fn parse_answer(
    wire: &[u8],
    rrtype: u16,
    ttl: u32,
    rd_length: usize,
    header: usize,
    rdata_end: usize,
    meta: &mut ResponseMeta,
) -> Option<()> {
    let rdata = header + 10;
    if rrtype != TYPE_OPT {
        meta.min_ttl = Some(match meta.min_ttl {
            Some(current) if current <= ttl => current,
            _ => ttl,
        });
        meta.answer_ttl_offsets.push(to_offset(header + 4)?);
    }

    if rd_length == 0 {
        return Some(());
    }

    match rrtype {
        TYPE_A => {
            if rd_length != 4 {
                return None;
            }
            push_ip(meta, format_ipv4(&wire[rdata..rdata_end]));
        }
        TYPE_AAAA => {
            if rd_length != 16 {
                return None;
            }
            push_ip(meta, format_ipv6(&wire[rdata..rdata_end]));
        }
        TYPE_CNAME => {
            let (name, end) = unpack_name(wire, rdata, rdata_end)?;
            if end != rdata_end {
                return None;
            }
            push_chain_target(meta, &name, ChainKind::Cname);
        }
        TYPE_SVCB | TYPE_HTTPS => {
            if rd_length < 2 {
                return None;
            }
            if rd_length == 2 {
                return Some(());
            }
            let (name, end) = unpack_name(wire, rdata + 2, rdata_end)?;
            if end > rdata_end {
                return None;
            }
            push_chain_target(meta, &name, ChainKind::Svcb);
        }
        _ => {}
    }
    Some(())
}

fn parse_soa(
    wire: &[u8],
    ttl: u32,
    rd_length: usize,
    rdata: usize,
    rdata_end: usize,
) -> Option<(u32, u32)> {
    if rd_length == 0 {
        return Some((ttl, 0));
    }
    let (_, offset) = unpack_name(wire, rdata, rdata_end)?;
    if offset == rdata_end {
        return Some((ttl, 0));
    }
    let (_, offset) = unpack_name(wire, offset, rdata_end)?;
    let remaining = rdata_end - offset;
    match remaining {
        0 | 4 | 8 | 12 | 16 => Some((ttl, 0)),
        20 => Some((ttl, read_u32(wire, offset + 16)?)),
        _ => None,
    }
}

fn push_chain_target(meta: &mut ResponseMeta, name: &str, kind: ChainKind) {
    let trimmed = name.trim_matches(is_go_space);
    let lowered = trimmed.to_ascii_lowercase();
    let domain = lowered.strip_suffix('.').unwrap_or(&lowered);
    if domain.is_empty() {
        return;
    }
    meta.chain_targets.push(ChainTarget {
        domain: domain.to_string(),
        kind,
    });
}

fn is_go_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\n' | '\x0b' | '\x0c' | '\r')
}

fn push_ip(meta: &mut ResponseMeta, address: String) {
    if meta.ips.iter().any(|seen| seen == &address) {
        return;
    }
    meta.ips.push(address);
}

pub fn format_ipv4(bytes: &[u8]) -> String {
    format!("{}.{}.{}.{}", bytes[0], bytes[1], bytes[2], bytes[3])
}

pub fn format_ipv6(bytes: &[u8]) -> String {
    let mut raw = [0u8; 16];
    raw.copy_from_slice(&bytes[..16]);
    let mapped = raw[..10].iter().all(|byte| *byte == 0) && raw[10] == 0xff && raw[11] == 0xff;
    if mapped {
        return format_ipv4(&raw[12..16]);
    }
    let mut segments = [0u16; 8];
    for (index, segment) in segments.iter_mut().enumerate() {
        *segment = u16::from_be_bytes([raw[index * 2], raw[index * 2 + 1]]);
    }
    std::net::Ipv6Addr::from(segments).to_string()
}

fn to_offset(offset: usize) -> Option<u16> {
    u16::try_from(offset).ok()
}

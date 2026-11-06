//! Wire-format helpers of the DNS cache, mirroring the Go code they replaced byte for byte.
//!
//! Everything here works on the raw response the upstream sent. Two details are deliberately
//! copied from the Go implementations instead of being "improved":
//!
//! * the cache key is built from the question exactly like `appendQuestionKey` did: labels are
//!   lowercased byte-wise, joined with `.`, compression pointers are followed (up to 64 jumps) and
//!   the key ends in `:qtype:qclass`;
//! * owner/target names are decoded with the same presentation escaping as miekg/dns
//!   `UnpackDomainName` (`.` is re-escaped, bytes outside `' '..='~'` become `\DDD`, the root name
//!   is `"."`), because the chain targets are compared against rule patterns downstream.

/// Longest key `appendQuestionKey` can build: a 255-byte name plus `:65535:65535`.
pub const MAX_KEY_LEN: usize = 256 + 12;

const TYPE_A: u16 = 1;
const TYPE_CNAME: u16 = 5;
const TYPE_SOA: u16 = 6;
const TYPE_AAAA: u16 = 28;
const TYPE_OPT: u16 = 41;
const TYPE_SVCB: u16 = 64;
const TYPE_HTTPS: u16 = 65;

/// `maxDomainNameWireOctets` in miekg/dns.
const MAX_NAME_WIRE_OCTETS: i32 = 255;
/// `maxCompressionPointers` in miekg/dns: `(255+1)/2 - 2`.
const MAX_COMPRESSION_POINTERS: usize = 126;
/// Jump limit of the key builder (`appendQuestionKey`), not of the name decoder.
const MAX_KEY_POINTER_JUMPS: usize = 64;

/// The question of a query turned into the cache key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuestionKey {
    /// `name:qtype:qclass`, lowercased, without the trailing dot of the name.
    pub key: Vec<u8>,
    /// Length of the name part at the front of `key`.
    pub name_len: usize,
    pub qtype: u16,
    pub qclass: u16,
}

/// Which record put a domain in a response chain.
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

/// One CNAME/SVCB/HTTPS target of the answer section, normalized like Go did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChainTarget {
    pub domain: String,
    pub kind: ChainKind,
}

/// Everything `putMsg` used to read off the unpacked `*dns.Msg`, read straight from the wire.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ResponseMeta {
    /// TC bit of the header.
    pub truncated: bool,
    /// Low four bits of the header flags.
    pub rcode: u8,
    /// `anCount` of the header; equals `len(msg.Answer)` for every message this parser accepts.
    pub answer_count: u16,
    /// Minimum TTL over the non-OPT answers, else the authority SOA fallback.
    pub min_ttl: Option<u32>,
    /// TTL offsets of the non-OPT answer records.
    pub answer_ttl_offsets: Vec<u16>,
    /// TTL offsets of the non-OPT records right after the question when the answer is empty.
    pub authority_ttl_offsets: Vec<u16>,
    /// CNAME/SVCB/HTTPS targets of the answer section, in record order.
    pub chain_targets: Vec<ChainTarget>,
    /// A/AAAA answers as Go printed them, deduplicated in record order.
    pub ips: Vec<String>,
    /// `strings.Join(ips, ",")`.
    pub resolved_ips: String,
}

/// Split parts of a key built by [`write_question_key`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyParts {
    pub key_len: usize,
    pub name_len: usize,
    pub qtype: u16,
    pub qclass: u16,
}

/// Builds the cache key of the first question in `wire` directly into `out` (no heap allocation).
///
/// Returns `None` for anything the Go builder rejected — short buffers, `qdCount == 0`, reserved
/// label types, truncated labels, more than 64 compression jumps — or when `out` is too small.
/// A compression chain longer than [`MAX_KEY_LEN`] is rejected here; the Go builder would have
/// grown its buffer instead, but such a response cannot pass the 255-byte name budget of
/// [`parse_response`], so it could never have matched a cache entry anyway.
pub fn write_question_key(wire: &[u8], out: &mut [u8]) -> Option<KeyParts> {
    if wire.len() < 12 || read_u16(wire, 4)? == 0 {
        return None;
    }

    let mut length_written = 0usize;
    let mut current = 12usize;
    let mut end: Option<usize> = None;
    let mut jumps = 0usize;

    loop {
        if current >= wire.len() {
            return None;
        }
        let length = wire[current] as usize;
        if length == 0 {
            if end.is_none() {
                end = Some(current + 1);
            }
            break;
        }
        match length & 0xc0 {
            0xc0 => {
                if current + 2 > wire.len() {
                    return None;
                }
                if end.is_none() {
                    end = Some(current + 2);
                }
                jumps += 1;
                if jumps > MAX_KEY_POINTER_JUMPS {
                    return None;
                }
                current = (read_u16(wire, current)? & 0x3fff) as usize;
                continue;
            }
            0 => {}
            _ => return None,
        }
        current += 1;
        if current + length > wire.len() {
            return None;
        }
        if length_written > 0 {
            push_byte(out, &mut length_written, b'.')?;
        }
        for &byte in &wire[current..current + length] {
            push_byte(out, &mut length_written, byte.to_ascii_lowercase())?;
        }
        current += length;
    }

    let end = end?;
    let name_len = length_written;
    let qtype = read_u16(wire, end)?;
    let qclass = read_u16(wire, end + 2)?;
    push_byte(out, &mut length_written, b':')?;
    push_decimal(out, &mut length_written, qtype)?;
    push_byte(out, &mut length_written, b':')?;
    push_decimal(out, &mut length_written, qclass)?;

    Some(KeyParts {
        key_len: length_written,
        name_len,
        qtype,
        qclass,
    })
}

/// Builds the cache key of the first question in `wire`.
pub fn question_key(wire: &[u8]) -> Option<QuestionKey> {
    let mut buffer = [0u8; MAX_KEY_LEN];
    let parts = write_question_key(wire, &mut buffer)?;
    Some(QuestionKey {
        key: buffer[..parts.key_len].to_vec(),
        name_len: parts.name_len,
        qtype: parts.qtype,
        qclass: parts.qclass,
    })
}

/// Parses the sections the cache needs; `None` means "do not cache this answer".
///
/// The walk mirrors what `dns.Msg.Unpack` accepted, not just what RFC 1035 allows: a message that
/// ends exactly on a record boundary is accepted with the declared-but-missing records dropped,
/// a zero-length rdata is accepted for every type (`noRdata`), and a SOA whose rdata stops on a
/// field boundary keeps its remaining fields zero. Those cases only exist in malformed upstream
/// answers, but the answer the old cache stored for them is reproduced exactly.
///
/// Two deliberate differences remain. Rdata of record types the cache does not read is skipped by
/// `rdLength` instead of being validated field by field (so a broken MX/TXT is cached instead of
/// dropped), and a response whose question section is cut mid-field is rejected here while
/// `unpackQuestion` swallowed that error and reported a zero `qclass`. Both only affect malformed
/// data; valid answers take exactly the same path as before.
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
        // `unpackRRslice` stops without an error when the message ends on a record boundary and
        // the header still claims more records; the parsed sections are simply shorter. Keep that
        // (only malformed or hand-cut messages get here, but the old cache stored them too).
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

/// Copies `wire` and overwrites the query ID and every indexed TTL.
pub fn patch_response(wire: &[u8], offsets: &[u16], query_id: u16, ttl: u32) -> Option<Vec<u8>> {
    let mut patched = vec![0u8; wire.len()];
    if patch_response_into(wire, offsets, query_id, ttl, &mut patched) {
        Some(patched)
    } else {
        None
    }
}

/// Same as [`patch_response`] but writes into a caller-owned buffer of exactly `wire.len()` bytes.
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

    // `noRdata` in miekg/dns: a zero-length record is accepted for every type without unpacking
    // its body, so an empty A/AAAA/CNAME/SVCB is "valid but carries nothing".
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
            // Priority only: the generated unpacker returns as soon as the rdata slice ends.
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

/// Parses an SOA rdata like miekg/dns did and returns `(header TTL, MINIMUM)`.
///
/// The generated unpacker returns as soon as the rdata slice ends, and `UnpackRRWithHeader` only
/// insists that the whole rdata was consumed. A record that stops exactly on a field boundary is
/// therefore accepted with the remaining fields zero, which is why the MINIMUM here can be `0`.
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

/// Decodes a name the way `dns.UnpackDomainName` did, escaping for presentation.
///
/// `limit` is the slice miekg/dns unpacked: the whole message for owner names, the record's rdata
/// for a CNAME/SVCB target, so a compression pointer cannot reach past it.
fn unpack_name(wire: &[u8], start: usize, limit: usize) -> Option<(String, usize)> {
    let limit = limit.min(wire.len());
    let mut text = String::new();
    let mut offset = start;
    let mut budget = MAX_NAME_WIRE_OCTETS;
    let mut pointers = 0usize;
    let mut consumed: Option<usize> = None;

    loop {
        if offset >= limit {
            return None;
        }
        let byte = wire[offset] as usize;
        offset += 1;
        match byte & 0xc0 {
            0x00 => {
                if byte == 0 {
                    if consumed.is_none() {
                        consumed = Some(offset);
                    }
                    break;
                }
                if offset + byte > limit {
                    return None;
                }
                budget -= (byte + 1) as i32;
                if budget <= 0 {
                    return None;
                }
                for &label in &wire[offset..offset + byte] {
                    push_escaped(&mut text, label);
                }
                text.push('.');
                offset += byte;
            }
            0xc0 => {
                if offset >= limit {
                    return None;
                }
                let low = wire[offset] as usize;
                offset += 1;
                if consumed.is_none() {
                    consumed = Some(offset);
                }
                pointers += 1;
                if pointers > MAX_COMPRESSION_POINTERS {
                    return None;
                }
                offset = ((byte & 0x3f) << 8) | low;
            }
            _ => return None,
        }
    }

    if text.is_empty() {
        text.push('.');
    }
    Some((text, consumed?))
}

fn push_escaped(text: &mut String, byte: u8) {
    if matches!(
        byte,
        b'.' | b' ' | b'\'' | b'@' | b';' | b'(' | b')' | b'"' | b'\\'
    ) {
        text.push('\\');
        text.push(byte as char);
    } else if !(b' '..=b'~').contains(&byte) {
        text.push('\\');
        text.push((b'0' + byte / 100) as char);
        text.push((b'0' + (byte / 10) % 10) as char);
        text.push((b'0' + byte % 10) as char);
    } else {
        text.push(byte as char);
    }
}

/// `strings.TrimSuffix(strings.ToLower(strings.TrimSpace(name)), ".")`, skipping empty results.
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

/// The ASCII half of Go's `unicode.IsSpace` (`\v` included, unlike Rust's ASCII trim).
fn is_go_space(character: char) -> bool {
    matches!(character, ' ' | '\t' | '\n' | '\x0b' | '\x0c' | '\r')
}

fn push_ip(meta: &mut ResponseMeta, address: String) {
    if meta.ips.iter().any(|seen| seen == &address) {
        return;
    }
    meta.ips.push(address);
}

fn format_ipv4(bytes: &[u8]) -> String {
    format!("{}.{}.{}.{}", bytes[0], bytes[1], bytes[2], bytes[3])
}

/// `net.IP.String()`: IPv4-mapped addresses print dotted, everything else in RFC 5952 form.
fn format_ipv6(bytes: &[u8]) -> String {
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

fn push_byte(out: &mut [u8], length: &mut usize, byte: u8) -> Option<()> {
    if *length >= out.len() {
        return None;
    }
    out[*length] = byte;
    *length += 1;
    Some(())
}

fn push_decimal(out: &mut [u8], length: &mut usize, value: u16) -> Option<()> {
    let mut digits = [0u8; 5];
    let mut count = 0usize;
    let mut remaining = value;
    loop {
        digits[count] = b'0' + (remaining % 10) as u8;
        count += 1;
        remaining /= 10;
        if remaining == 0 {
            break;
        }
    }
    while count > 0 {
        count -= 1;
        push_byte(out, length, digits[count])?;
    }
    Some(())
}

fn read_u16(wire: &[u8], offset: usize) -> Option<u16> {
    let bytes = wire.get(offset..offset + 2)?;
    Some(u16::from_be_bytes([bytes[0], bytes[1]]))
}

fn read_u32(wire: &[u8], offset: usize) -> Option<u32> {
    let bytes = wire.get(offset..offset + 4)?;
    Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

#[cfg(test)]
mod tests;

//! EDNS(0) options: encoding, decoding, padding and UDP truncation.
//!
//! The OPT pseudo-record is the only record this module writes: owner root, type 41, CLASS holds
//! the advertised UDP payload size and TTL packs extended rcode, version, DO and the reserved
//! bits (RFC 6891). Its rdata is a sequence of `(code, length, value)` TLVs.

use std::net::IpAddr;

use crate::bits::{read_u16, read_u32};
use crate::build::types::{
    OPTION_COOKIE, OPTION_ECS, OPTION_EDE, OPTION_NSID, OPTION_PADDING, TYPE_OPT,
};
use crate::message::parse_header;
use crate::name::unpack_name;

const FLAG_TC: u16 = 0x0200;

/// Client Subnet option payload (RFC 7871).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EcsOption {
    pub family: u16,
    pub source_prefix: u8,
    pub scope_prefix: u8,
    /// The significant address octets (already truncated to the source prefix length).
    pub address: Vec<u8>,
}

impl EcsOption {
    pub fn new(family: u16, source_prefix: u8, scope_prefix: u8, address: Vec<u8>) -> Self {
        Self {
            family,
            source_prefix,
            scope_prefix,
            address,
        }
    }

    /// Builds an option from a full address, truncating it to the source prefix like resolvers do.
    pub fn from_ip(address: IpAddr, source_prefix: u8, scope_prefix: u8) -> Self {
        match address {
            IpAddr::V4(address) => {
                let source = source_prefix.min(32);
                let scope = scope_prefix.min(32);
                let octets = address.octets();
                let keep = usize::from(source).div_ceil(8);
                Self::new(1, source, scope, octets[..keep].to_vec())
            }
            IpAddr::V6(address) => {
                let source = source_prefix.min(128);
                let scope = scope_prefix.min(128);
                let octets = address.octets();
                let keep = usize::from(source).div_ceil(8);
                Self::new(2, source, scope, octets[..keep].to_vec())
            }
        }
    }
}

/// Extended DNS Error payload (RFC 8914).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EdeOption {
    pub code: u16,
    pub text: String,
}

impl EdeOption {
    pub fn new(code: u16, text: impl Into<String>) -> Self {
        Self {
            code,
            text: text.into(),
        }
    }
}

/// One EDNS TLV.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EdnsOption {
    Ecs(EcsOption),
    Ede(EdeOption),
    Padding(Vec<u8>),
    Nsid(Vec<u8>),
    Cookie(Vec<u8>),
    Unknown { code: u16, data: Vec<u8> },
}

impl EdnsOption {
    /// A padding option of `len` zero octets (RFC 7830 requires zeros).
    pub fn padding(len: usize) -> Self {
        EdnsOption::Padding(vec![0; len])
    }

    /// The option code written on the wire.
    pub fn code(&self) -> u16 {
        match self {
            EdnsOption::Ecs(_) => OPTION_ECS,
            EdnsOption::Ede(_) => OPTION_EDE,
            EdnsOption::Padding(_) => OPTION_PADDING,
            EdnsOption::Nsid(_) => OPTION_NSID,
            EdnsOption::Cookie(_) => OPTION_COOKIE,
            EdnsOption::Unknown { code, .. } => *code,
        }
    }

    /// Appends the TLV (code, length, value) to `out`.
    pub fn encode(&self, out: &mut Vec<u8>) -> bool {
        let data = self.data();
        if data.len() > u16::MAX as usize {
            return false;
        }
        out.extend_from_slice(&self.code().to_be_bytes());
        out.extend_from_slice(&(data.len() as u16).to_be_bytes());
        out.extend_from_slice(&data);
        true
    }

    fn data(&self) -> Vec<u8> {
        match self {
            EdnsOption::Ecs(ecs) => {
                let mut data = Vec::with_capacity(4 + ecs.address.len());
                data.extend_from_slice(&ecs.family.to_be_bytes());
                data.push(ecs.source_prefix);
                data.push(ecs.scope_prefix);
                data.extend_from_slice(&ecs.address);
                data
            }
            EdnsOption::Ede(ede) => {
                let mut data = Vec::with_capacity(2 + ede.text.len());
                data.extend_from_slice(&ede.code.to_be_bytes());
                data.extend_from_slice(ede.text.as_bytes());
                data
            }
            EdnsOption::Padding(data)
            | EdnsOption::Nsid(data)
            | EdnsOption::Cookie(data)
            | EdnsOption::Unknown { data, .. } => data.clone(),
        }
    }
}

/// The OPT pseudo-record a message should carry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OptBuilder {
    /// Advertised UDP payload size, written into the CLASS field.
    pub udp_size: u16,
    /// DNSSEC OK bit.
    pub do_bit: bool,
    /// High eight bits of the extended rcode.
    pub ext_rcode: u8,
    /// EDNS version (`0` for EDNS(0)).
    pub version: u8,
    /// The remaining 15 reserved bits.
    pub z: u16,
    pub options: Vec<EdnsOption>,
}

impl Default for OptBuilder {
    fn default() -> Self {
        Self {
            udp_size: 1232,
            do_bit: false,
            ext_rcode: 0,
            version: 0,
            z: 0,
            options: Vec::new(),
        }
    }
}

impl OptBuilder {
    /// A builder with `udp_size` and all other fields at their defaults.
    pub fn new(udp_size: u16) -> Self {
        Self {
            udp_size,
            ..Self::default()
        }
    }

    pub fn with_do_bit(mut self, do_bit: bool) -> Self {
        self.do_bit = do_bit;
        self
    }

    /// The advertised UDP payload size (CLASS field).
    pub fn udp_size(&self) -> u16 {
        self.udp_size
    }

    /// The DNSSEC OK bit.
    pub fn do_bit(&self) -> bool {
        self.do_bit
    }

    /// The high eight bits of the extended rcode.
    pub fn ext_rcode(&self) -> u8 {
        self.ext_rcode
    }

    /// The EDNS version.
    pub fn version(&self) -> u8 {
        self.version
    }

    /// The 15 reserved bits of the TTL.
    pub fn z(&self) -> u16 {
        self.z
    }

    /// The EDNS option list.
    pub fn options(&self) -> &[EdnsOption] {
        &self.options
    }

    pub fn push_option(mut self, option: EdnsOption) -> Self {
        self.options.push(option);
        self
    }

    /// Appends the complete OPT resource record to `out`.
    pub fn encode(&self, out: &mut Vec<u8>) -> bool {
        let mut rdata = Vec::new();
        for option in &self.options {
            if !option.encode(&mut rdata) {
                return false;
            }
        }
        if rdata.len() > u16::MAX as usize {
            return false;
        }

        out.push(0); // root owner name
        out.extend_from_slice(&TYPE_OPT.to_be_bytes());
        out.extend_from_slice(&self.udp_size.to_be_bytes());
        let ttl = (u32::from(self.ext_rcode) << 24)
            | (u32::from(self.version) << 16)
            | (u32::from(self.do_bit) << 15)
            | u32::from(self.z & 0x7fff);
        out.extend_from_slice(&ttl.to_be_bytes());
        out.extend_from_slice(&(rdata.len() as u16).to_be_bytes());
        out.extend_from_slice(&rdata);
        true
    }
}

/// The decoded contents of an OPT record.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OptInfo {
    pub udp_size: u16,
    pub ext_rcode: u8,
    pub version: u8,
    pub do_bit: bool,
    pub z: u16,
    pub options: Vec<EdnsOption>,
}

/// Reads the first OPT record from the additional section.
pub fn parse_opt(wire: &[u8]) -> Option<OptInfo> {
    let walked = walk(wire)?;
    let opt = walked.opt?;
    let options = decode_options(&wire[opt.rdata_start..opt.rdata_end])?;
    Some(OptInfo {
        udp_size: opt.udp_size,
        ext_rcode: (opt.ttl >> 24) as u8,
        version: (opt.ttl >> 16) as u8,
        do_bit: opt.ttl & 0x8000 != 0,
        z: (opt.ttl & 0x7fff) as u16,
        options,
    })
}

/// Pads `message` with an EDNS Padding option so its total length is a multiple of `block`.
///
/// Any padding options already present are discarded and replaced by one option with the exact
/// number of zero octets needed (RFC 7830/8467). The OPT RDLEN is rewritten; the record count is
/// unchanged. Returns `false` when the message has no OPT record, `block` is zero, or the result
/// would need a value that does not fit RDLEN.
pub fn pad_to_block(message: &mut Vec<u8>, block: usize) -> bool {
    if block == 0 {
        return false;
    }
    let walked = match walk(message) {
        Some(walked) => walked,
        None => return false,
    };
    let opt = match walked.opt {
        Some(opt) => opt,
        None => return false,
    };

    // Keep every option except padding, byte for byte.
    let mut rebuilt = Vec::new();
    let mut data = &message[opt.rdata_start..opt.rdata_end];
    while !data.is_empty() {
        if data.len() < 4 {
            return false;
        }
        let code = match read_u16(data, 0) {
            Some(code) => code,
            None => return false,
        };
        let length = match read_u16(data, 2) {
            Some(length) => usize::from(length),
            None => return false,
        };
        if data.len() < 4 + length {
            return false;
        }
        if code != OPTION_PADDING {
            rebuilt.extend_from_slice(&data[..4 + length]);
        }
        data = &data[4 + length..];
    }

    let suffix_len = message.len() - opt.rdata_end;
    let base = opt.rdata_start + rebuilt.len() + suffix_len;
    let pad_len = (block - (base + 4) % block) % block;
    if pad_len > u16::MAX as usize {
        return false;
    }
    let new_rdlen = rebuilt.len() + 4 + pad_len;
    if new_rdlen > u16::MAX as usize {
        return false;
    }

    let mut out = Vec::with_capacity(base + 4 + pad_len);
    out.extend_from_slice(&message[..opt.rdata_start]);
    out.extend_from_slice(&rebuilt);
    out.extend_from_slice(&OPTION_PADDING.to_be_bytes());
    out.extend_from_slice(&(pad_len as u16).to_be_bytes());
    out.resize(out.len() + pad_len, 0);
    out.extend_from_slice(&message[opt.rdata_end..]);
    out[opt.rdlen_offset..opt.rdlen_offset + 2].copy_from_slice(&(new_rdlen as u16).to_be_bytes());

    debug_assert_eq!(out.len() % block, 0);
    *message = out;
    true
}

/// Truncates a UDP response to at most `max` bytes.
///
/// The TC bit is set and every answer, authority and additional record is dropped. The question
/// is always kept; the OPT record is kept when it still fits. Returns `true` when the message was
/// over `max` and was reduced to fit, `false` when it already fit or could not be parsed (or when
/// even the header plus question is larger than `max`).
pub fn truncate_udp(message: &mut Vec<u8>, max: usize) -> bool {
    if message.len() <= max {
        return false;
    }
    let walked = match walk(message) {
        Some(walked) => walked,
        None => return false,
    };

    let opt_bytes = walked
        .opt
        .map(|opt| &message[opt.record_start..opt.record_end]);
    let keep_opt = opt_bytes.is_some_and(|opt| walked.question_end + opt.len() <= max);

    let mut out = Vec::with_capacity(max.min(message.len()));
    out.extend_from_slice(&message[..walked.question_end]);
    if let Some(opt) = opt_bytes {
        if keep_opt {
            out.extend_from_slice(opt);
        }
    }
    if out.len() > max {
        // The question itself does not fit; truncating further would break DNS semantics.
        return false;
    }

    let flags = read_u16(message, 2).unwrap_or(0) | FLAG_TC;
    out[2..4].copy_from_slice(&flags.to_be_bytes());
    out[4..6].copy_from_slice(&walked.question_count.to_be_bytes());
    out[6..8].copy_from_slice(&0u16.to_be_bytes());
    out[8..10].copy_from_slice(&0u16.to_be_bytes());
    out[10..12].copy_from_slice(&u16::from(keep_opt).to_be_bytes());
    *message = out;
    true
}

/// Where the OPT record lives in a walked message.
#[derive(Debug, Clone, Copy)]
struct OptSpan {
    udp_size: u16,
    ttl: u32,
    /// Offset of the two RDLEN octets.
    rdlen_offset: usize,
    rdata_start: usize,
    rdata_end: usize,
    record_start: usize,
    record_end: usize,
}

#[derive(Debug, Clone, Copy)]
struct Walk {
    question_count: u16,
    question_end: usize,
    opt: Option<OptSpan>,
}

/// Walks the questions and every record, remembering the first OPT record in the additional
/// section. Strict: a declared record that is not present makes the walk fail.
fn walk(wire: &[u8]) -> Option<Walk> {
    let header = parse_header(wire)?;
    let mut offset = 12usize;
    for _ in 0..header.question_count {
        let (_, next) = unpack_name(wire, offset, wire.len())?;
        offset = next.checked_add(4)?;
        if offset > wire.len() {
            return None;
        }
    }
    let question_end = offset;

    let additional_start = usize::from(header.answer_count) + usize::from(header.authority_count);
    let total = additional_start + usize::from(header.additional_count);
    let mut opt = None;

    for index in 0..total {
        let record_start = offset;
        let (_, name_end) = unpack_name(wire, offset, wire.len())?;
        let rrtype = read_u16(wire, name_end)?;
        let udp_size = read_u16(wire, name_end + 2)?;
        let ttl = read_u32(wire, name_end + 4)?;
        let rd_length = usize::from(read_u16(wire, name_end + 8)?);
        let rdata_start = name_end.checked_add(10)?;
        let rdata_end = rdata_start.checked_add(rd_length)?;
        if rdata_end > wire.len() {
            return None;
        }
        if index >= additional_start && rrtype == TYPE_OPT && opt.is_none() {
            opt = Some(OptSpan {
                udp_size,
                ttl,
                rdlen_offset: name_end + 8,
                rdata_start,
                rdata_end,
                record_start,
                record_end: rdata_end,
            });
        }
        offset = rdata_end;
    }

    Some(Walk {
        question_count: header.question_count,
        question_end,
        opt,
    })
}

pub(crate) fn decode_options(data: &[u8]) -> Option<Vec<EdnsOption>> {
    let mut options = Vec::new();
    let mut data = data;
    while !data.is_empty() {
        let code = read_u16(data, 0)?;
        let length = usize::from(read_u16(data, 2)?);
        if data.len() < 4 + length {
            return None;
        }
        options.push(decode_option(code, &data[4..4 + length])?);
        data = &data[4 + length..];
    }
    Some(options)
}

fn decode_option(code: u16, data: &[u8]) -> Option<EdnsOption> {
    Some(match code {
        OPTION_ECS => {
            if data.len() < 4 {
                return None;
            }
            EdnsOption::Ecs(EcsOption::new(
                read_u16(data, 0)?,
                data[2],
                data[3],
                data[4..].to_vec(),
            ))
        }
        OPTION_EDE => {
            if data.len() < 2 {
                return None;
            }
            EdnsOption::Ede(EdeOption::new(
                read_u16(data, 0)?,
                String::from_utf8_lossy(&data[2..]).into_owned(),
            ))
        }
        OPTION_PADDING => EdnsOption::Padding(data.to_vec()),
        OPTION_NSID => EdnsOption::Nsid(data.to_vec()),
        OPTION_COOKIE => EdnsOption::Cookie(data.to_vec()),
        _ => EdnsOption::Unknown {
            code,
            data: data.to_vec(),
        },
    })
}

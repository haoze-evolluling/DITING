use std::net::IpAddr;

use crate::bits::{read_u16, read_u32};
use crate::build::edns::{decode_options, EdnsOption, OptBuilder};
use crate::build::message::{encode_record, ResourceRecord};
use crate::build::name::NameWriter;
use crate::build::parse_rdata::parse_rdata;
use crate::build::rdata::RData;
use crate::build::types::{SVCB_KEY_IPV6HINT, TYPE_OPT};
use crate::message::{parse_header, parse_question, Question};
use crate::name::unpack_name;

const FLAG_QR: u16 = 0x8000;
const FLAG_TC: u16 = 0x0200;
const RCODE_MASK: u16 = 0x000f;
const EXT_RCODE_SHIFT: u32 = 24;
const VERSION_SHIFT: u32 = 16;
const DO_BIT: u32 = 0x8000;
const Z_MASK: u32 = 0x7fff;
const DEFAULT_UDP_SIZE: u16 = 1232;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedMessage {
    pub id: u16,
    pub flags: u16,
    pub questions: Vec<Question>,
    pub answers: Vec<ResourceRecord>,
    pub authorities: Vec<ResourceRecord>,
    pub additionals: Vec<ResourceRecord>,
    pub opt: Option<OptBuilder>,
}

impl ParsedMessage {
    pub fn parse(wire: &[u8]) -> Option<Self> {
        let header = parse_header(wire)?;

        let mut offset = 12usize;
        let mut questions = Vec::with_capacity(usize::from(header.question_count));
        for _ in 0..header.question_count {
            let (question, next) = parse_question(wire, offset, true)?;
            if next <= offset {
                return None;
            }
            questions.push(question);
            offset = next;
        }
        if questions.len() != usize::from(header.question_count) {
            return None;
        }

        let mut answers = Vec::with_capacity(usize::from(header.answer_count));
        let mut authorities = Vec::with_capacity(usize::from(header.authority_count));
        let mut additionals = Vec::with_capacity(usize::from(header.additional_count));
        let mut opt = None;

        offset = parse_section(
            wire,
            offset,
            header.answer_count,
            false,
            &mut answers,
            &mut opt,
        )?;
        offset = parse_section(
            wire,
            offset,
            header.authority_count,
            false,
            &mut authorities,
            &mut opt,
        )?;
        parse_section(
            wire,
            offset,
            header.additional_count,
            true,
            &mut additionals,
            &mut opt,
        )?;

        Some(Self {
            id: header.id,
            flags: header.flags,
            questions,
            answers,
            authorities,
            additionals,
            opt,
        })
    }

    pub fn to_wire(&self) -> Option<Vec<u8>> {
        let question_count = u16::try_from(self.questions.len()).ok()?;
        let answer_count = u16::try_from(self.answers.len()).ok()?;
        let authority_count = u16::try_from(self.authorities.len()).ok()?;
        let additional_count =
            u16::try_from(self.additionals.len() + usize::from(self.opt.is_some())).ok()?;

        let mut out = Vec::with_capacity(512);
        out.extend_from_slice(&self.id.to_be_bytes());
        out.extend_from_slice(&self.flags.to_be_bytes());
        out.extend_from_slice(&question_count.to_be_bytes());
        out.extend_from_slice(&answer_count.to_be_bytes());
        out.extend_from_slice(&authority_count.to_be_bytes());
        out.extend_from_slice(&additional_count.to_be_bytes());

        let mut names = NameWriter::new();
        for question in &self.questions {
            if !names.write_name(&mut out, &question.name) {
                return None;
            }
            out.extend_from_slice(&question.qtype.to_be_bytes());
            out.extend_from_slice(&question.qclass.to_be_bytes());
        }
        for record in &self.answers {
            encode_record(record, &mut names, &mut out)?;
        }
        for record in &self.authorities {
            encode_record(record, &mut names, &mut out)?;
        }
        for record in &self.additionals {
            encode_record(record, &mut names, &mut out)?;
        }
        if let Some(opt) = &self.opt {
            if !opt.encode(&mut out) {
                return None;
            }
        }
        Some(out)
    }

    pub fn rcode(&self) -> u8 {
        let low = (self.flags & RCODE_MASK) as u8;
        match &self.opt {
            Some(opt) => (opt.ext_rcode << 4) | low,
            None => low,
        }
    }

    pub fn set_rcode(&mut self, rcode: u8) {
        if rcode <= 0x0f {
            self.flags = (self.flags & !RCODE_MASK) | u16::from(rcode);
            if let Some(opt) = &mut self.opt {
                opt.ext_rcode = 0;
            }
        } else {
            self.flags &= !RCODE_MASK;
            let extended = rcode >> 4;
            self.opt
                .get_or_insert_with(|| OptBuilder::new(DEFAULT_UDP_SIZE))
                .ext_rcode = extended;
        }
    }

    pub fn is_response(&self) -> bool {
        self.flags & FLAG_QR != 0
    }

    pub fn question(&self) -> Option<&Question> {
        self.questions.first()
    }

    pub fn answer_addrs(&self) -> Vec<IpAddr> {
        self.answers
            .iter()
            .filter_map(|record| match &record.rdata {
                RData::A(address) => Some(IpAddr::V4(*address)),
                RData::Aaaa(address) => Some(IpAddr::V6(*address)),
                _ => None,
            })
            .collect()
    }

    pub fn answer_cnames(&self) -> Vec<String> {
        self.answers
            .iter()
            .filter_map(|record| match &record.rdata {
                RData::Cname(target) => Some(target.clone()),
                _ => None,
            })
            .collect()
    }

    /// Removes ``ipv6hint`` parameters from HTTPS/SVCB records in every section.
    ///
    /// Returns whether anything changed. Used when IPv6 answers are suppressed so
    /// clients cannot learn addresses from service bindings.
    pub fn strip_ipv6_hints(&mut self) -> bool {
        let mut changed = false;
        for record in self
            .answers
            .iter_mut()
            .chain(self.authorities.iter_mut())
            .chain(self.additionals.iter_mut())
        {
            match &mut record.rdata {
                RData::Https(svcb) | RData::Svcb(svcb) => {
                    let before = svcb.params.len();
                    svcb.params.retain(|param| param.key != SVCB_KEY_IPV6HINT);
                    changed |= svcb.params.len() != before;
                }
                _ => {}
            }
        }
        changed
    }

    pub fn take_opt(&mut self) -> Option<OptBuilder> {
        self.opt.take()
    }

    pub fn opt_options(&self) -> &[EdnsOption] {
        match &self.opt {
            Some(opt) => &opt.options,
            None => &[],
        }
    }

    pub fn push_opt_option(&mut self, option: EdnsOption) {
        self.opt
            .get_or_insert_with(|| OptBuilder::new(DEFAULT_UDP_SIZE))
            .options
            .push(option);
    }

    pub fn remove_opt_option(&mut self, code: u16) -> bool {
        let Some(opt) = &mut self.opt else {
            return false;
        };
        let before = opt.options.len();
        opt.options.retain(|option| option.code() != code);
        opt.options.len() != before
    }

    pub fn truncate_to(&mut self, max: usize) -> bool {
        match self.to_wire() {
            Some(wire) if wire.len() <= max => return false,
            None => return false,
            Some(_) => {}
        }

        self.flags |= FLAG_TC;
        while !self.additionals.is_empty() && !self.fits(max) {
            self.additionals.pop();
        }
        while !self.authorities.is_empty() && !self.fits(max) {
            self.authorities.pop();
        }
        while !self.answers.is_empty() && !self.fits(max) {
            self.answers.pop();
        }
        true
    }

    fn fits(&self, max: usize) -> bool {
        self.to_wire().is_some_and(|wire| wire.len() <= max)
    }
}

fn parse_section(
    wire: &[u8],
    mut offset: usize,
    count: u16,
    recognize_opt: bool,
    records: &mut Vec<ResourceRecord>,
    opt: &mut Option<OptBuilder>,
) -> Option<usize> {
    for _ in 0..count {
        let (name, next) = unpack_name(wire, offset, wire.len())?;
        if next.checked_add(10)? > wire.len() {
            return None;
        }
        let rtype = read_u16(wire, next)?;
        let class = read_u16(wire, next + 2)?;
        let ttl = read_u32(wire, next + 4)?;
        let rdlength = usize::from(read_u16(wire, next + 8)?);
        let rdata_start = next + 10;
        let rdata_end = rdata_start.checked_add(rdlength)?;
        if rdata_end > wire.len() {
            return None;
        }

        if recognize_opt && rtype == TYPE_OPT && opt.is_none() && name == "." {
            let options = decode_options(&wire[rdata_start..rdata_end])?;
            *opt = Some(OptBuilder {
                udp_size: class,
                do_bit: ttl & DO_BIT != 0,
                ext_rcode: (ttl >> EXT_RCODE_SHIFT) as u8,
                version: (ttl >> VERSION_SHIFT) as u8,
                z: (ttl & Z_MASK) as u16,
                options,
            });
        } else {
            let rdata = parse_rdata(wire, rdata_start, rdlength, rtype)?;
            records.push(ResourceRecord {
                name,
                rtype,
                class,
                ttl,
                rdata,
            });
        }
        offset = rdata_end;
    }
    Some(offset)
}

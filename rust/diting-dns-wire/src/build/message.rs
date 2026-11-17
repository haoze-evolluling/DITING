//! Message synthesis: a small, move-based builder on top of the existing readers.
//!
//! The builder owns the header flags and the three resource-record sections. [`MessageBuilder::finish`]
//! serializes them with [`NameWriter`] so repeated owner names and the legal rdata names share
//! compression pointers, then appends the OPT pseudo-record last in the additional section.

use crate::build::edns::OptBuilder;
use crate::build::name::NameWriter;
use crate::build::rdata::RData;
use crate::message::{parse_header, parse_question, Question};

const FLAG_QR: u16 = 0x8000;
const FLAG_AA: u16 = 0x0400;
const FLAG_TC: u16 = 0x0200;
const FLAG_RD: u16 = 0x0100;
const FLAG_RA: u16 = 0x0080;
const FLAG_AD: u16 = 0x0020;
const FLAG_CD: u16 = 0x0010;
const RCODE_MASK: u16 = 0x000f;

/// One resource record ready to be written into a section.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceRecord {
    /// Owner name in presentation form (escaped like [`crate::unpack_name`] output).
    pub name: String,
    pub rtype: u16,
    pub class: u16,
    pub ttl: u32,
    pub rdata: RData,
}

impl ResourceRecord {
    pub fn new(
        name: impl Into<String>,
        rtype: u16,
        class: u16,
        ttl: u32,
        rdata: RData,
    ) -> Self {
        Self {
            name: name.into(),
            rtype,
            class,
            ttl,
            rdata,
        }
    }
}

/// A DNS query or response being assembled.
#[derive(Debug, Clone)]
pub struct MessageBuilder {
    id: u16,
    flags: u16,
    questions: Vec<Question>,
    answers: Vec<ResourceRecord>,
    authorities: Vec<ResourceRecord>,
    additionals: Vec<ResourceRecord>,
    opt: Option<OptBuilder>,
}

impl MessageBuilder {
    /// Starts a reply to `query`, or returns `None` when it is not a single-question request.
    ///
    /// The ID and the first question are echoed verbatim, the RD and CD bits are copied and QR is
    /// set. Everything else (AA, RA, TC, rcode and the answer sections) starts empty so the caller
    /// spells out what the synthesized answer means.
    pub fn reply_to(query: &[u8]) -> Option<Self> {
        let header = parse_header(query)?;
        if header.is_response() || header.question_count != 1 {
            return None;
        }
        let (question, _) = parse_question(query, 12, true)?;
        Some(Self {
            id: header.id,
            flags: FLAG_QR | (header.flags & (FLAG_RD | FLAG_CD)),
            questions: vec![question],
            answers: Vec::new(),
            authorities: Vec::new(),
            additionals: Vec::new(),
            opt: None,
        })
    }

    /// Starts a recursive query (`RD=1`) with one question and ID zero.
    pub fn query(name: &str, qtype: u16, qclass: u16) -> Self {
        Self {
            id: 0,
            flags: FLAG_RD,
            questions: vec![Question {
                name: name.to_string(),
                qtype,
                qclass,
            }],
            answers: Vec::new(),
            authorities: Vec::new(),
            additionals: Vec::new(),
            opt: None,
        }
    }

    /// Overrides the message ID (for example a fresh random ID for a query).
    pub fn set_id(mut self, id: u16) -> Self {
        self.id = id;
        self
    }

    /// Replaces the low four rcode bits. Extended rcodes live in [`OptBuilder::ext_rcode`].
    pub fn set_rcode(mut self, rcode: u8) -> Self {
        self.flags = (self.flags & !RCODE_MASK) | (u16::from(rcode) & RCODE_MASK);
        self
    }

    pub fn set_authoritative(self, authoritative: bool) -> Self {
        self.set_flag(FLAG_AA, authoritative)
    }

    pub fn set_recursion_available(self, available: bool) -> Self {
        self.set_flag(FLAG_RA, available)
    }

    pub fn set_truncated(self, truncated: bool) -> Self {
        self.set_flag(FLAG_TC, truncated)
    }

    pub fn set_recursion_desired(self, desired: bool) -> Self {
        self.set_flag(FLAG_RD, desired)
    }

    pub fn set_authentic_data(self, authentic: bool) -> Self {
        self.set_flag(FLAG_AD, authentic)
    }

    pub fn set_checking_disabled(self, disabled: bool) -> Self {
        self.set_flag(FLAG_CD, disabled)
    }

    pub fn push_answer(mut self, record: ResourceRecord) -> Self {
        self.answers.push(record);
        self
    }

    pub fn push_authority(mut self, record: ResourceRecord) -> Self {
        self.authorities.push(record);
        self
    }

    pub fn push_additional(mut self, record: ResourceRecord) -> Self {
        self.additionals.push(record);
        self
    }

    /// Attaches the OPT pseudo-record, which [`finish`](Self::finish) writes last.
    pub fn with_opt(mut self, opt: OptBuilder) -> Self {
        self.opt = Some(opt);
        self
    }

    /// Same as [`with_opt`](Self::with_opt); kept for call sites that read better as a setter.
    pub fn set_opt(self, opt: OptBuilder) -> Self {
        self.with_opt(opt)
    }

    /// Removes a previously attached OPT record.
    pub fn clear_opt(mut self) -> Self {
        self.opt = None;
        self
    }

    /// Serializes the message, or returns `None` on an unencodable name/section.
    pub fn finish(self) -> Option<Vec<u8>> {
        let question_count = u16::try_from(self.questions.len()).ok()?;
        let answer_count = u16::try_from(self.answers.len()).ok()?;
        let authority_count = u16::try_from(self.authorities.len()).ok()?;
        let additional_count = u16::try_from(
            self.additionals.len() + usize::from(self.opt.is_some()),
        )
        .ok()?;

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
            // The OPT record is always the last record of the additional section.
            if !opt.encode(&mut out) {
                return None;
            }
        }
        Some(out)
    }

    fn set_flag(mut self, mask: u16, enabled: bool) -> Self {
        if enabled {
            self.flags |= mask;
        } else {
            self.flags &= !mask;
        }
        self
    }
}

fn encode_record(
    record: &ResourceRecord,
    names: &mut NameWriter,
    out: &mut Vec<u8>,
) -> Option<()> {
    if !names.write_name(out, &record.name) {
        return None;
    }
    out.extend_from_slice(&record.rtype.to_be_bytes());
    out.extend_from_slice(&record.class.to_be_bytes());
    out.extend_from_slice(&record.ttl.to_be_bytes());
    let length_at = out.len();
    out.extend_from_slice(&[0, 0]);
    let rdata_start = out.len();
    if !record.rdata.encode(names, out) {
        return None;
    }
    let length = u16::try_from(out.len() - rdata_start).ok()?;
    out[length_at..length_at + 2].copy_from_slice(&length.to_be_bytes());
    Some(())
}

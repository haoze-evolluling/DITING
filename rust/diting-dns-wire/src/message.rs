//! Header and question parsing; the two readers upstream validation and the cache key need.

use crate::bits::read_u16;
use crate::name::unpack_name;

/// The fixed 12-byte DNS message header.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MessageHeader {
    pub id: u16,
    pub flags: u16,
    pub question_count: u16,
    pub answer_count: u16,
    pub authority_count: u16,
    pub additional_count: u16,
}

impl MessageHeader {
    /// The `QR` bit (`dns.Msg.Response`).
    pub fn is_response(self) -> bool {
        self.flags & 0x8000 != 0
    }
}

/// One question section entry with the presentation name (`dns.Question.Name`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Question {
    pub name: String,
    pub qtype: u16,
    pub qclass: u16,
}

/// Reads the fixed header; `None` for anything shorter than 12 bytes.
pub fn parse_header(wire: &[u8]) -> Option<MessageHeader> {
    if wire.len() < 12 {
        return None;
    }
    Some(MessageHeader {
        id: read_u16(wire, 0)?,
        flags: read_u16(wire, 2)?,
        question_count: read_u16(wire, 4)?,
        answer_count: read_u16(wire, 6)?,
        authority_count: read_u16(wire, 8)?,
        additional_count: read_u16(wire, 10)?,
    })
}

/// Reads one question at `offset`.
///
/// `strict` selects between the two readers the Go side has: the cache key builder requires the
/// full `name + qtype + qclass`; `dns.Msg.Unpack` accepts a message that stops right after the
/// name (or after the type) and reports a zero field, which is what upstream validation used to
/// see. Both follow compression pointers through the whole message.
pub fn parse_question(wire: &[u8], offset: usize, strict: bool) -> Option<(Question, usize)> {
    let (name, mut next) = unpack_name(wire, offset, wire.len())?;
    if strict && next + 4 > wire.len() {
        return None;
    }
    let qtype = match read_u16(wire, next) {
        Some(value) => {
            next += 2;
            value
        }
        None => {
            return Some((
                Question {
                    name,
                    qtype: 0,
                    qclass: 0,
                },
                wire.len(),
            ))
        }
    };
    if next == wire.len() {
        return Some((
            Question {
                name,
                qtype,
                qclass: 0,
            },
            next,
        ));
    }
    let qclass = match read_u16(wire, next) {
        Some(value) => {
            next += 2;
            value
        }
        None => {
            return Some((
                Question {
                    name,
                    qtype,
                    qclass: 0,
                },
                wire.len(),
            ))
        }
    };
    Some((
        Question {
            name,
            qtype,
            qclass,
        },
        next,
    ))
}

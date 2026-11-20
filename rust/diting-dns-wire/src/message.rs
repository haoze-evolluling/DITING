use crate::bits::read_u16;
use crate::name::unpack_name;

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
    pub fn is_response(self) -> bool {
        self.flags & 0x8000 != 0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Question {
    pub name: String,
    pub qtype: u16,
    pub qclass: u16,
}

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

use crate::bits::read_u16;

pub const MAX_KEY_LEN: usize = 256 + 12;
const MAX_KEY_POINTER_JUMPS: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuestionKey {
    pub key: Vec<u8>,
    pub name_len: usize,
    pub qtype: u16,
    pub qclass: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyParts {
    pub key_len: usize,
    pub name_len: usize,
    pub qtype: u16,
    pub qclass: u16,
}

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

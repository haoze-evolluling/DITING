//! Cache-key building of the first question (`appendQuestionKey`).

use crate::bits::read_u16;

/// Longest key `appendQuestionKey` can build: a 255-byte name plus `:65535:65535`.
pub const MAX_KEY_LEN: usize = 256 + 12;
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

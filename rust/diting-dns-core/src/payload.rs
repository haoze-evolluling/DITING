//! The binary layouts shared with `android/engine/dns_core_payload.go`.
//!
//! Answer inspection request (Go -> kernel):
//!
//! ```text
//! | u8 layout | u32 count | count × ( u8 rrtype | u16 length | bytes address ) |
//! ```
//!
//! Answer inspection response (kernel -> Go):
//!
//! ```text
//! | u8 layout | u8 flags | u32 length | bytes address text |
//! ```
//!
//! `flags` bit 0 is "blocked". Both sides pin the same layout; a drifted version byte, a length
//! that disagrees with the payload or trailing bytes are hard errors, never a misread.

use crate::answer::AnswerEntry;

/// Must match `dnsCorePayloadLayoutVersion` in `android/engine/dns_core_payload.go`.
pub const LAYOUT_VERSION: u8 = 1;

/// The answer is a null block (`isUpstreamBlockedMsg`).
pub const FLAG_BLOCKED: u8 = 1 << 0;

/// Every frame is a layout byte, a count, then `rrtype`/`length`/bytes per record.
const REQUEST_HEADER: usize = 1 + 4;
const RECORD_HEADER: usize = 1 + 2;
const RESPONSE_HEADER: usize = 1 + 1 + 4;

/// Reads an answer inspection request, borrowing the addresses out of `payload`.
pub fn decode_answer_request(payload: &[u8]) -> Option<Vec<AnswerEntry<'_>>> {
    if payload.len() < REQUEST_HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let count = u32::from_le_bytes(payload[1..5].try_into().ok()?) as usize;
    // Every record needs a type, a length and the address itself, so a count larger than the
    // remaining bytes allows is already invalid.
    if count > (payload.len() - REQUEST_HEADER) / RECORD_HEADER {
        return None;
    }

    let mut entries = Vec::with_capacity(count);
    let mut position = REQUEST_HEADER;
    for _ in 0..count {
        if payload.len() - position < RECORD_HEADER {
            return None;
        }
        let rrtype = payload[position];
        let length =
            u16::from_le_bytes(payload[position + 1..position + 3].try_into().ok()?) as usize;
        position += RECORD_HEADER;
        if payload.len() - position < length {
            return None;
        }
        entries.push(AnswerEntry {
            rrtype,
            address: &payload[position..position + length],
        });
        position += length;
    }
    if position != payload.len() {
        return None;
    }
    Some(entries)
}

/// Encodes the inspection result.
pub fn encode_answer_response(blocked: bool, addresses: &str) -> Vec<u8> {
    let text = addresses.as_bytes();
    let mut out = Vec::with_capacity(RESPONSE_HEADER + text.len());
    out.push(LAYOUT_VERSION);
    out.push(if blocked { FLAG_BLOCKED } else { 0 });
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text);
    out
}

/// Reads the inspection result.
pub fn decode_answer_response(payload: &[u8]) -> Option<(bool, String)> {
    if payload.len() < RESPONSE_HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let flags = payload[1];
    if flags & !FLAG_BLOCKED != 0 {
        return None;
    }
    let length = u32::from_le_bytes(payload[2..6].try_into().ok()?) as usize;
    if payload.len() - RESPONSE_HEADER != length {
        return None;
    }
    let text = std::str::from_utf8(&payload[RESPONSE_HEADER..]).ok()?;
    Some((flags & FLAG_BLOCKED != 0, text.to_string()))
}

#[cfg(test)]
mod tests;

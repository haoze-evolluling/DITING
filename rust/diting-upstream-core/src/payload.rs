//! The binary layouts shared with `android/engine/upstream_native*.go`.
//!
//! * Target response: `u8 layout | text host | text port`.
//! * Dial address: `u8 layout | text address`.
//! * Tuning: `u8 layout | i64 × 17` in [`crate::tuning::Tuning::fields`] order.
//! * Pool close-all: `u8 layout | u32 count | u64 id × count`.
//!
//! `text` is `u32 length | bytes`; every integer is little-endian. A drifted version byte, a length
//! that disagrees with the payload or a trailing byte is a hard error.

use crate::tuning::Tuning;

/// Must match `upstreamPayloadLayoutVersion` in Go.
pub const LAYOUT_VERSION: u8 = 1;

/// Number of `i64` fields in a tuning payload.
pub const TUNING_FIELDS: usize = 17;

struct Reader<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(payload: &'a [u8]) -> Option<Self> {
        if payload.first().copied()? != LAYOUT_VERSION {
            return None;
        }
        Some(Self {
            payload,
            position: 1,
        })
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        if self.payload.len() - self.position < length {
            return None;
        }
        let slice = &self.payload[self.position..self.position + length];
        self.position += length;
        Some(slice)
    }

    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }

    fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }

    fn i64(&mut self) -> Option<i64> {
        Some(i64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }

    fn text(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        Some(String::from_utf8_lossy(self.take(length)?).into_owned())
    }

    fn finished(&self) -> bool {
        self.position == self.payload.len()
    }
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

/// Encodes a target response.
pub fn encode_target(host: &str, port: &str) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    put_text(&mut out, host);
    put_text(&mut out, port);
    out
}

/// Decodes a target response.
pub fn decode_target(payload: &[u8]) -> Option<(String, String)> {
    let mut reader = Reader::new(payload)?;
    let host = reader.text()?;
    let port = reader.text()?;
    if !reader.finished() {
        return None;
    }
    Some((host, port))
}

/// Encodes a dial-address response.
pub fn encode_address(address: &str) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    put_text(&mut out, address);
    out
}

/// Decodes a dial-address response.
pub fn decode_address(payload: &[u8]) -> Option<String> {
    let mut reader = Reader::new(payload)?;
    let address = reader.text()?;
    if !reader.finished() {
        return None;
    }
    Some(address)
}

/// Encodes the tuning table.
pub fn encode_tuning(tuning: &Tuning) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + TUNING_FIELDS * 8);
    out.push(LAYOUT_VERSION);
    for field in tuning.fields() {
        out.extend_from_slice(&field.to_le_bytes());
    }
    out
}

/// Decodes the tuning table.
pub fn decode_tuning(payload: &[u8]) -> Option<Tuning> {
    let mut reader = Reader::new(payload)?;
    let mut fields = [0i64; TUNING_FIELDS];
    for field in fields.iter_mut() {
        *field = reader.i64()?;
    }
    if !reader.finished() {
        return None;
    }
    Some(Tuning::from_fields(fields))
}

/// Encodes the ids a close-all returned.
pub fn encode_ids(ids: &[u64]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 4 + ids.len() * 8);
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&(ids.len() as u32).to_le_bytes());
    for id in ids {
        out.extend_from_slice(&id.to_le_bytes());
    }
    out
}

/// Decodes the ids a close-all returned.
pub fn decode_ids(payload: &[u8]) -> Option<Vec<u64>> {
    let mut reader = Reader::new(payload)?;
    let count = reader.u32()? as usize;
    if count > payload.len() / 8 {
        return None;
    }
    let mut ids = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        ids.push(reader.u64()?);
    }
    if !reader.finished() {
        return None;
    }
    Some(ids)
}

#[cfg(test)]
mod tests;

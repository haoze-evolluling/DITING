//! The binary layout the response parser shares with `android/engine/dns_cache_native.go`.
//!
//! Everything is little endian and the payload starts with a layout byte, so a mismatched
//! Go/Rust pair is a loud rejection instead of a misread field. The metadata crosses the
//! boundary once per cache write, not per query, so the encoding favours a simple walk over
//! compactness.
//!
//! ```text
//! response: u8 layout
//!           u16 answer_count
//!           u8  rcode
//!           u8  flags              bit0 truncated, bit1 min_ttl present
//!           u32 min_ttl            (0 when absent)
//!           u16 answer_ttl_offset_count | u16 × offsets
//!           u16 authority_ttl_offset_count | u16 × offsets
//!           u16 chain_target_count | (u8 kind, text domain) ×
//!           u16 ip_count | text ×
//!           text resolved_ips
//! ```
//!
//! `text` is a `u32` length followed by UTF-8 bytes. `kind` is `0` CNAME and `1` SVCB
//! (HTTPS records are reported as SVCB, exactly like the Go `chainTarget` list did).
//! The rejection payload is empty: a wire the parser cannot read simply must not be cached.

use crate::wire::ResponseMeta;

/// Layout version of the payload below; `dnsCachePayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

const FLAG_TRUNCATED: u8 = 1 << 0;
const FLAG_MIN_TTL: u8 = 1 << 1;

/// Encodes the metadata a cache write stores.
pub fn encode_response_meta(meta: &ResponseMeta) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&meta.answer_count.to_le_bytes());
    out.push(meta.rcode);
    let mut flags = 0u8;
    if meta.truncated {
        flags |= FLAG_TRUNCATED;
    }
    if meta.min_ttl.is_some() {
        flags |= FLAG_MIN_TTL;
    }
    out.push(flags);
    out.extend_from_slice(&meta.min_ttl.unwrap_or(0).to_le_bytes());

    push_u16_list(&mut out, &meta.answer_ttl_offsets);
    push_u16_list(&mut out, &meta.authority_ttl_offsets);

    out.extend_from_slice(&(meta.chain_targets.len() as u16).to_le_bytes());
    for target in &meta.chain_targets {
        out.push(target.kind.code());
        push_text(&mut out, &target.domain);
    }

    out.extend_from_slice(&(meta.ips.len() as u16).to_le_bytes());
    for ip in &meta.ips {
        push_text(&mut out, ip);
    }
    push_text(&mut out, &meta.resolved_ips);
    out
}

/// Decodes [`encode_response_meta`]'s output; the Go decoder reads the same fields.
///
/// Only tests use this side of the layout, but keeping it here pins the encoding and the
/// decoding against each other instead of against a hand-written byte array.
#[cfg(test)]
pub fn decode_response_meta(data: &[u8]) -> Result<ResponseMeta, String> {
    use crate::wire::{ChainKind, ChainTarget};
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(format!(
            "response layout {layout}, expected {LAYOUT_VERSION}"
        ));
    }
    let answer_count = reader.u16("answer_count")?;
    let rcode = reader.u8("rcode")?;
    let flags = reader.u8("flags")?;
    let min_ttl = reader.u32("min_ttl")?;
    let answer_ttl_offsets = reader.u16_list("answer_ttl_offsets")?;
    let authority_ttl_offsets = reader.u16_list("authority_ttl_offsets")?;

    let target_count = reader.u16("chain_target_count")? as usize;
    let mut chain_targets = Vec::with_capacity(target_count);
    for _ in 0..target_count {
        let code = reader.u8("kind")?;
        let kind =
            ChainKind::from_code(code).ok_or_else(|| format!("unknown chain kind {code}"))?;
        chain_targets.push(ChainTarget {
            domain: reader.text("domain")?,
            kind,
        });
    }

    let ip_count = reader.u16("ip_count")? as usize;
    let mut ips = Vec::with_capacity(ip_count);
    for _ in 0..ip_count {
        ips.push(reader.text("ip")?);
    }
    let resolved_ips = reader.text("resolved_ips")?;
    reader.expect_end()?;

    Ok(ResponseMeta {
        truncated: flags & FLAG_TRUNCATED != 0,
        rcode,
        answer_count,
        min_ttl: if flags & FLAG_MIN_TTL != 0 {
            Some(min_ttl)
        } else {
            None
        },
        answer_ttl_offsets,
        authority_ttl_offsets,
        chain_targets,
        ips,
        resolved_ips,
    })
}

fn push_u16_list(out: &mut Vec<u8>, values: &[u16]) {
    out.extend_from_slice(&(values.len() as u16).to_le_bytes());
    for value in values {
        out.extend_from_slice(&value.to_le_bytes());
    }
}

fn push_text(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(&(value.len() as u32).to_le_bytes());
    out.extend_from_slice(value.as_bytes());
}

#[cfg(test)]
struct Reader<'a> {
    data: &'a [u8],
    position: usize,
}

#[cfg(test)]
impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, position: 0 }
    }

    fn remaining(&self) -> usize {
        self.data.len() - self.position
    }

    fn u8(&mut self, field: &str) -> Result<u8, String> {
        if self.remaining() < 1 {
            return Err(format!("response payload is truncated ({field})"));
        }
        let value = self.data[self.position];
        self.position += 1;
        Ok(value)
    }

    fn u16(&mut self, field: &str) -> Result<u16, String> {
        if self.remaining() < 2 {
            return Err(format!("response payload is truncated ({field})"));
        }
        let value = u16::from_le_bytes([self.data[self.position], self.data[self.position + 1]]);
        self.position += 2;
        Ok(value)
    }

    fn u32(&mut self, field: &str) -> Result<u32, String> {
        if self.remaining() < 4 {
            return Err(format!("response payload is truncated ({field})"));
        }
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&self.data[self.position..self.position + 4]);
        self.position += 4;
        Ok(u32::from_le_bytes(bytes))
    }

    fn u16_list(&mut self, field: &str) -> Result<Vec<u16>, String> {
        let count = self.u16(field)? as usize;
        let mut values = Vec::with_capacity(count);
        for _ in 0..count {
            values.push(self.u16(field)?);
        }
        Ok(values)
    }

    fn text(&mut self, field: &str) -> Result<String, String> {
        let length = self.u32(field)? as usize;
        if self.remaining() < length {
            return Err(format!("response payload is truncated ({field})"));
        }
        let slice = &self.data[self.position..self.position + length];
        self.position += length;
        String::from_utf8(slice.to_vec()).map_err(|_| format!("{field} is not valid UTF-8"))
    }

    fn expect_end(&self) -> Result<(), String> {
        if self.remaining() == 0 {
            Ok(())
        } else {
            Err(format!(
                "response payload has {} trailing bytes",
                self.remaining()
            ))
        }
    }
}

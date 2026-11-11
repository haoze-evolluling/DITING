//! The binary layouts shared with `desktop/service/internal/core/safebrowsing_native.go`.
//!
//! Everything is little endian and starts with a layout byte, so a stale Go/Rust pair is a loud
//! rejection instead of a misread field. `text` is a `u16` length followed by UTF-8 bytes.
//!
//! ```text
//! plan:  u8 layout | u8 flags | u8 need_count | 32-byte digest * need_count | text question
//! apply: u8 layout | u8 service | u8 queried_count | 32-byte digest * queried_count
//!        | u16 received_count | (text) * received_count
//! ```
//!
//! `plan.flags` carries three booleans: bit 0 `empty` (the host has no candidate digest at all),
//! bit 1 `found` (every prefix was cached, so `blocked` is the answer) and bit 2 `blocked`.
//!
//! The digests travel as 32 raw bytes rather than 64 hex characters: one hand-built label is
//! built here anyway, and hex would only double the payload per query.

use crate::engine::Plan;
use crate::hash::{HostnameHash, HASH_SIZE};

/// Layout version of every payload below; `sbPayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

const PLAN_EMPTY: u8 = 1 << 0;
const PLAN_FOUND: u8 = 1 << 1;
const PLAN_BLOCKED: u8 = 1 << 2;

/// Decoded `apply` request: which service, what was asked, what came back.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApplyRequest {
    pub service: u8,
    pub queried: Vec<HostnameHash>,
    pub received: Vec<String>,
}

/// Encodes one [`Plan`].
pub fn encode_plan(plan: &Plan) -> Vec<u8> {
    let mut flags = 0u8;
    if plan.empty {
        flags |= PLAN_EMPTY;
    }
    if plan.found {
        flags |= PLAN_FOUND;
    }
    if plan.blocked {
        flags |= PLAN_BLOCKED;
    }

    let mut out =
        Vec::with_capacity(3 + plan.need_query.len() * HASH_SIZE + 2 + plan.question.len());
    out.push(LAYOUT_VERSION);
    out.push(flags);
    out.push(plan.need_query.len() as u8);
    for hash in &plan.need_query {
        out.extend_from_slice(hash);
    }
    push_text(&mut out, &plan.question);
    out
}

/// Reads a plan back; used by the ABI round-trip tests and by nothing else.
#[cfg(test)]
pub(crate) fn decode_plan(data: &[u8]) -> Result<Plan, String> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(format!("plan layout {layout}, expected {LAYOUT_VERSION}"));
    }
    let flags = reader.u8("flags")?;
    let count = reader.u8("need_count")? as usize;
    let mut need_query = Vec::with_capacity(count);
    for _ in 0..count {
        need_query.push(reader.digest()?);
    }
    let question = reader.text("question")?;
    reader.expect_end()?;
    Ok(Plan {
        empty: flags & PLAN_EMPTY != 0,
        found: flags & PLAN_FOUND != 0,
        blocked: flags & PLAN_BLOCKED != 0,
        need_query,
        question,
    })
}

/// Decodes an `apply` request written by the Go side.
pub fn decode_apply(data: &[u8]) -> Result<ApplyRequest, String> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(format!("apply layout {layout}, expected {LAYOUT_VERSION}"));
    }
    let service = reader.u8("service")?;
    let queried_count = reader.u8("queried_count")? as usize;
    let mut queried = Vec::with_capacity(queried_count);
    for _ in 0..queried_count {
        queried.push(reader.digest()?);
    }
    let received_count = reader.u16("received_count")? as usize;
    let mut received = Vec::with_capacity(received_count);
    for _ in 0..received_count {
        received.push(reader.text("received")?);
    }
    reader.expect_end()?;
    Ok(ApplyRequest {
        service,
        queried,
        received,
    })
}

fn push_text(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(&(value.len() as u16).to_le_bytes());
    out.extend_from_slice(value.as_bytes());
}

struct Reader<'a> {
    data: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, position: 0 }
    }

    fn remaining(&self) -> usize {
        self.data.len().saturating_sub(self.position)
    }

    fn u8(&mut self, field: &str) -> Result<u8, String> {
        if self.remaining() < 1 {
            return Err(format!("payload is truncated ({field})"));
        }
        let value = self.data[self.position];
        self.position += 1;
        Ok(value)
    }

    fn u16(&mut self, field: &str) -> Result<u16, String> {
        if self.remaining() < 2 {
            return Err(format!("payload is truncated ({field})"));
        }
        let value = u16::from_le_bytes([self.data[self.position], self.data[self.position + 1]]);
        self.position += 2;
        Ok(value)
    }

    fn digest(&mut self) -> Result<HostnameHash, String> {
        if self.remaining() < HASH_SIZE {
            return Err("payload is truncated (digest)".to_string());
        }
        let mut hash = [0u8; HASH_SIZE];
        hash.copy_from_slice(&self.data[self.position..self.position + HASH_SIZE]);
        self.position += HASH_SIZE;
        Ok(hash)
    }

    fn text(&mut self, field: &str) -> Result<String, String> {
        let length = self.u16(&format!("{field} length"))? as usize;
        if self.remaining() < length {
            return Err(format!("payload is truncated ({field})"));
        }
        let bytes = &self.data[self.position..self.position + length];
        self.position += length;
        String::from_utf8(bytes.to_vec()).map_err(|_| format!("{field} is not UTF-8"))
    }

    fn expect_end(&self) -> Result<(), String> {
        if self.remaining() != 0 {
            return Err(format!("payload has {} trailing bytes", self.remaining()));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests;

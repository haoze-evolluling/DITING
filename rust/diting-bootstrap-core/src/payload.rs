//! The binary layouts shared with `android/engine/bootstrap_native.go`.
//!
//! Plan request (Go -> kernel), passed alongside `now_ns` and the three random rolls:
//!
//! ```text
//! | u8 layout | u32 count | count × ( u32 id_len | id bytes | f64 weight ) |
//! ```
//!
//! Plan response (kernel -> Go):
//!
//! ```text
//! | u8 layout | i32 primary (-1 = none) | u8 exploration | u32 fallback_count |
//! fallback_count × u32 index
//! ```
//!
//! Score response (kernel -> Go, test/observability path):
//!
//! ```text
//! | f64 weight | u8 cooling_down | f64 sample_count |
//! ```
//!
//! Integers are little-endian and floats are their IEEE-754 bits, also little-endian. Both sides
//! pin the version byte: a drifted byte, a count that disagrees with the payload or trailing bytes
//! are hard errors, never a misread.

use crate::engine::Plan;

/// Must match `bootstrapPayloadLayoutVersion` in `android/engine/bootstrap_native.go`.
pub const LAYOUT_VERSION: u8 = 1;

/// `f64 weight | u8 cooling | f64 sample_count`.
pub const SCORE_BYTES: usize = 8 + 1 + 8;

const ENTRIES_HEADER: usize = 1 + 4;
/// `u32 id_len` + `f64 weight`, before the id bytes.
const ENTRY_FIXED: usize = 4 + 8;
const PLAN_HEADER: usize = 1 + 4 + 1 + 4;

/// Reads the plan request's entries.
pub fn decode_plan_entries(payload: &[u8]) -> Option<Vec<(String, f64)>> {
    if payload.len() < ENTRIES_HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let count = u32::from_le_bytes(payload[1..5].try_into().ok()?) as usize;
    if count > (payload.len() - ENTRIES_HEADER) / ENTRY_FIXED {
        return None;
    }

    let mut entries = Vec::with_capacity(count);
    let mut position = ENTRIES_HEADER;
    for _ in 0..count {
        if payload.len() - position < ENTRY_FIXED {
            return None;
        }
        let id_len = u32::from_le_bytes(payload[position..position + 4].try_into().ok()?) as usize;
        position += 4;
        if payload.len() - position < id_len + 8 {
            return None;
        }
        let id = std::str::from_utf8(&payload[position..position + id_len])
            .ok()?
            .to_string();
        position += id_len;
        let weight = f64::from_le_bytes(payload[position..position + 8].try_into().ok()?);
        position += 8;
        entries.push((id, weight));
    }
    if position != payload.len() {
        return None;
    }
    Some(entries)
}

/// Encodes the plan request (the tests and the Go layout tests use the same shape).
pub fn encode_plan_entries(entries: &[(String, f64)]) -> Vec<u8> {
    let mut out = Vec::with_capacity(ENTRIES_HEADER + entries.len() * ENTRY_FIXED);
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
    for (id, weight) in entries {
        out.extend_from_slice(&(id.len() as u32).to_le_bytes());
        out.extend_from_slice(id.as_bytes());
        out.extend_from_slice(&weight.to_le_bytes());
    }
    out
}

/// Encodes the plan response.
pub fn encode_plan(plan: &Plan) -> Vec<u8> {
    let mut out = Vec::with_capacity(PLAN_HEADER + plan.fallbacks.len() * 4);
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(
        &plan
            .primary
            .map_or(-1i32, |index| index as i32)
            .to_le_bytes(),
    );
    out.push(u8::from(plan.exploration));
    out.extend_from_slice(&(plan.fallbacks.len() as u32).to_le_bytes());
    for index in &plan.fallbacks {
        out.extend_from_slice(&(*index as u32).to_le_bytes());
    }
    out
}

/// Encodes one score response.
pub fn encode_score(weight: f64, cooling_down: bool, sample_count: f64) -> [u8; SCORE_BYTES] {
    let mut out = [0u8; SCORE_BYTES];
    out[..8].copy_from_slice(&weight.to_le_bytes());
    out[8] = u8::from(cooling_down);
    out[9..].copy_from_slice(&sample_count.to_le_bytes());
    out
}

#[cfg(test)]
mod tests;

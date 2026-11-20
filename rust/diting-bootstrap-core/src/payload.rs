use crate::engine::Plan;

pub const LAYOUT_VERSION: u8 = 1;

pub const SCORE_BYTES: usize = 8 + 1 + 8;

const ENTRIES_HEADER: usize = 1 + 4;
const ENTRY_FIXED: usize = 4 + 8;
const PLAN_HEADER: usize = 1 + 4 + 1 + 4;

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

pub fn encode_score(weight: f64, cooling_down: bool, sample_count: f64) -> [u8; SCORE_BYTES] {
    let mut out = [0u8; SCORE_BYTES];
    out[..8].copy_from_slice(&weight.to_le_bytes());
    out[8] = u8::from(cooling_down);
    out[9..].copy_from_slice(&sample_count.to_le_bytes());
    out
}

#[cfg(test)]
mod tests;

use crate::tuning::TUNING;

pub const DOT_MAX_RESPONSE_LEN: usize = 4096;

const TRUNCATED_FLAG: u8 = 0x02;
const DNS_HEADER_LEN: usize = 12;

pub fn frame_into(query: &[u8], out: &mut [u8]) -> Option<usize> {
    if out.len() < query.len() + 2 {
        return None;
    }
    let prefix = (query.len() as u16).to_be_bytes();
    out[..2].copy_from_slice(&prefix);
    out[2..2 + query.len()].copy_from_slice(query);
    Some(query.len() + 2)
}

pub fn encode_length_prefixed(query: &[u8]) -> Vec<u8> {
    let mut out = vec![0u8; query.len() + 2];
    let written = frame_into(query, &mut out).expect("buffer is sized for the frame");
    out.truncate(written);
    out
}

pub fn tcp_response_length(header: &[u8]) -> Option<usize> {
    if header.len() < 2 {
        return None;
    }
    Some(u16::from_be_bytes([header[0], header[1]]) as usize)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DotLength {
    Valid(usize),
    Invalid(usize),
}

pub fn dot_response_length(header: &[u8]) -> Option<DotLength> {
    let length = tcp_response_length(header)?;
    if length == 0 || length > DOT_MAX_RESPONSE_LEN {
        Some(DotLength::Invalid(length))
    } else {
        Some(DotLength::Valid(length))
    }
}

pub fn is_truncated(raw: &[u8]) -> bool {
    raw.len() >= DNS_HEADER_LEN && raw[2] & TRUNCATED_FLAG != 0
}

pub fn initial_retry_delay_ns(ctx_value_ns: i64) -> i64 {
    if ctx_value_ns > 0 {
        ctx_value_ns
    } else {
        TUNING.plain_retry_default_ns
    }
}

pub fn first_deadline_ns(now_ns: i64, initial_ns: i64, deadline_ns: i64) -> i64 {
    let first = now_ns.saturating_add(initial_ns);
    if first > deadline_ns {
        deadline_ns
    } else {
        first
    }
}

pub fn retry_deadline_ns(
    now_ns: i64,
    initial_ns: i64,
    deadline_ns: i64,
    retry_index: u32,
) -> Option<i64> {
    if i64::from(retry_index) >= TUNING.plain_retry_limit {
        return None;
    }
    if now_ns >= deadline_ns {
        return None;
    }
    if retry_index == 0 {
        let step = now_ns.saturating_add(initial_ns.saturating_mul(2));
        Some(if step < deadline_ns {
            step
        } else {
            deadline_ns
        })
    } else {
        Some(deadline_ns)
    }
}

#[cfg(test)]
mod tests;

//! Wire framing shared by the four upstream protocols, plus the plain-UDP retry arithmetic.
//!
//! * TCP, DoT and DoQ all frame a DNS message with a 2-byte big-endian length. The Go code wrote
//!   `binary.BigEndian.PutUint16(buf, uint16(len(query)))` and appended the query; that casts the
//!   length to `uint16`, so a query longer than 65535 bytes would declare a truncated length while
//!   still sending every byte. The kernel keeps that cast (queries never get near it, but the bytes
//!   must stay identical).
//! * DoT validates the response length (`respLen == 0 || respLen > 4096` are errors); plain TCP does
//!   not (a zero length just yields an empty response, which the caller fails to unpack). The
//!   validity set lives here, the error text stays in Go.
//! * DoQ only strips its length prefix when it declares exactly the remaining bytes.
//! * `TC=1` on a UDP answer means the answer was truncated: bit 1 of the high flags byte (offset 2),
//!   and only for a message of at least 12 bytes.
//! * The plain-UDP retry loop waits `initial` for the first read, then `2 * initial` for the first
//!   retry and the full remaining budget for the second. `first_deadline_ns` /
//!   `retry_deadline_ns` are that arithmetic, including the "past the deadline is no retry" stop.

use crate::tuning::TUNING;

/// The largest response `executeDoTQuery` accepts (`respLen > dotMaxResponseLen` is an error).
pub const DOT_MAX_RESPONSE_LEN: usize = 4096;

/// The UDP (`TC`) flag is bit 1 of the high flags byte.
const TRUNCATED_FLAG: u8 = 0x02;
const DNS_HEADER_LEN: usize = 12;

/// Writes `u16(len)` (truncating exactly like Go's cast) followed by the query into `out`.
///
/// Returns the number of bytes written, or `None` when `out` cannot hold `query.len() + 2`.
pub fn frame_into(query: &[u8], out: &mut [u8]) -> Option<usize> {
    if out.len() < query.len() + 2 {
        return None;
    }
    let prefix = (query.len() as u16).to_be_bytes();
    out[..2].copy_from_slice(&prefix);
    out[2..2 + query.len()].copy_from_slice(query);
    Some(query.len() + 2)
}

/// The length-prefixed request bytes (tests and corpus use this shape).
pub fn encode_length_prefixed(query: &[u8]) -> Vec<u8> {
    let mut out = vec![0u8; query.len() + 2];
    let written = frame_into(query, &mut out).expect("buffer is sized for the frame");
    out.truncate(written);
    out
}

/// The 2-byte length prefix of a TCP/DoT response.
pub fn tcp_response_length(header: &[u8]) -> Option<usize> {
    if header.len() < 2 {
        return None;
    }
    Some(u16::from_be_bytes([header[0], header[1]]) as usize)
}

/// What `executeDoTQuery` does with the declared response length.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DotLength {
    Valid(usize),
    /// `0` or more than [`DOT_MAX_RESPONSE_LEN`]; Go reports `DoT invalid response length: N`.
    Invalid(usize),
}

/// The DoT response length rule.
pub fn dot_response_length(header: &[u8]) -> Option<DotLength> {
    let length = tcp_response_length(header)?;
    if length == 0 || length > DOT_MAX_RESPONSE_LEN {
        Some(DotLength::Invalid(length))
    } else {
        Some(DotLength::Valid(length))
    }
}

/// Whether a raw UDP answer has the truncation flag set.
pub fn is_truncated(raw: &[u8]) -> bool {
    raw.len() >= DNS_HEADER_LEN && raw[2] & TRUNCATED_FLAG != 0
}

/// How many bytes to skip at the front of a DoQ response: 2 when the prefix declares exactly the
/// remaining bytes, 0 otherwise (the Go code returned the raw stream in that case).
pub fn doq_skip(raw: &[u8]) -> usize {
    if raw.len() >= 2 {
        let declared = u16::from_be_bytes([raw[0], raw[1]]) as usize;
        if declared == raw.len() - 2 {
            return 2;
        }
    }
    0
}

/// `plainUDPRetryDelayFromContext`: a positive caller value wins, otherwise the tuning default.
pub fn initial_retry_delay_ns(ctx_value_ns: i64) -> i64 {
    if ctx_value_ns > 0 {
        ctx_value_ns
    } else {
        TUNING.plain_retry_default_ns
    }
}

/// The first read deadline: `now + initial`, clamped to the query deadline.
pub fn first_deadline_ns(now_ns: i64, initial_ns: i64, deadline_ns: i64) -> i64 {
    let first = now_ns.saturating_add(initial_ns);
    if first > deadline_ns {
        deadline_ns
    } else {
        first
    }
}

/// The deadline for the next attempt, or `None` when the retry limit is reached or the query
/// deadline has passed (`!now.Before(deadline)`).
///
/// `retry_index` is the zero-based retry that is about to run: retry 0 doubles the initial wait and
/// is clamped to the deadline, retry 1 gets the whole remaining budget.
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

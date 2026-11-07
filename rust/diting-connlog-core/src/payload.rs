//! The binary layout shared with `android/engine/connlog_native.go`.
//!
//! Mark request (Go -> kernel):
//!
//! ```text
//! | u8 layout | i32 port | i32 protocol |
//!   u32 prefix_len | prefix bytes | u32 app_len | app bytes |
//!   u32 dest_len | dest bytes | u32 reason_len | reason bytes |
//! ```
//!
//! A drifted version byte, a length that disagrees with the payload, trailing bytes or invalid
//! UTF-8 are hard errors, never a misread.

/// Must match `connLogPayloadLayoutVersion` in `android/engine/connlog_native.go`.
pub const LAYOUT_VERSION: u8 = 1;

const HEADER: usize = 1 + 4 + 4;

/// One decoded mark request.
#[derive(Debug, Clone, PartialEq)]
pub struct MarkRequest {
    pub prefix: String,
    pub app: String,
    pub dest: String,
    pub port: i32,
    pub protocol: i32,
    pub reason: String,
}

/// Reads a mark request.
pub fn decode_mark(payload: &[u8]) -> Option<MarkRequest> {
    if payload.len() < HEADER || payload[0] != LAYOUT_VERSION {
        return None;
    }
    let port = i32::from_le_bytes(payload[1..5].try_into().ok()?);
    let protocol = i32::from_le_bytes(payload[5..9].try_into().ok()?);
    let mut position = HEADER;
    let prefix = read_text(payload, &mut position)?;
    let app = read_text(payload, &mut position)?;
    let dest = read_text(payload, &mut position)?;
    let reason = read_text(payload, &mut position)?;
    if position != payload.len() {
        return None;
    }
    Some(MarkRequest {
        prefix,
        app,
        dest,
        port,
        protocol,
        reason,
    })
}

fn read_text(payload: &[u8], position: &mut usize) -> Option<String> {
    if payload.len() - *position < 4 {
        return None;
    }
    let length = u32::from_le_bytes(payload[*position..*position + 4].try_into().ok()?) as usize;
    *position += 4;
    if payload.len() - *position < length {
        return None;
    }
    let text = std::str::from_utf8(&payload[*position..*position + length])
        .ok()?
        .to_string();
    *position += length;
    Some(text)
}

/// Encodes a mark request (the tests and the Go layout tests use the same shape).
pub fn encode_mark(
    prefix: &str,
    app: &str,
    dest: &str,
    port: i32,
    protocol: i32,
    reason: &str,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER + prefix.len() + app.len() + dest.len() + reason.len());
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&port.to_le_bytes());
    out.extend_from_slice(&protocol.to_le_bytes());
    for text in [prefix, app, dest, reason] {
        out.extend_from_slice(&(text.len() as u32).to_le_bytes());
        out.extend_from_slice(text.as_bytes());
    }
    out
}

#[cfg(test)]
mod tests;

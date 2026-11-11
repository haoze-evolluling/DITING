//! PEM formatting and the tolerant reader the old Go side had.
//!
//! Go writes `ca.crt` with `pem.EncodeToMemory` (64-column base64, `\n` line ends) and reads it back
//! with `pem.Decode`, which tolerates text before the BEGIN line, ignores everything after the END
//! line and returns the first block. `pem-rfc7468`'s `decode_vec` wants the whole input to be one
//! document, so the scanning is spelled out here instead of adding another crate.

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;

/// One decoded block.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    pub label: String,
    pub der: Vec<u8>,
}

const BEGIN: &str = "-----BEGIN ";
const END: &str = "-----END ";
const DASHES: &str = "-----";

/// `pem.Decode` over the whole text: the first complete block, or `None`.
pub fn decode(text: &str) -> Option<Block> {
    let begin = text.find(BEGIN)?;
    let rest = &text[begin + BEGIN.len()..];
    let label_end = rest.find(DASHES)?;
    let label = rest[..label_end].trim();
    let body_start = begin + BEGIN.len() + label_end + DASHES.len();
    let body = &text[body_start.min(text.len())..];

    let end_marker = format!("{END}{label}{DASHES}");
    let body_end = body.find(&end_marker)?;
    let encoded: String = body[..body_end]
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect();
    let der = STANDARD.decode(encoded).ok()?;
    Some(Block {
        label: label.to_string(),
        der,
    })
}

/// `pem.EncodeToMemory`: 64 columns of base64 with a trailing newline.
pub fn encode(label: &str, der: &[u8]) -> String {
    let encoded = STANDARD.encode(der);
    let mut out = String::with_capacity(encoded.len() + encoded.len() / 64 + 64);
    out.push_str(BEGIN);
    out.push_str(label);
    out.push_str(DASHES);
    out.push('\n');
    for chunk in encoded.as_bytes().chunks(64) {
        out.push_str(std::str::from_utf8(chunk).unwrap_or_default());
        out.push('\n');
    }
    out.push_str(END);
    out.push_str(label);
    out.push_str(DASHES);
    out.push('\n');
    out
}

#[cfg(test)]
mod tests;

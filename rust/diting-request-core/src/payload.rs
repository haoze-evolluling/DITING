//! The binary layout shared with `android/engine/request_native_payload.go`.
//!
//! Rule set (Go -> kernel, `diting_request_new`):
//!
//! ```text
//! | i64 rule count | (str kind, str pattern) * count |
//! ```
//!
//! Match request (Go -> kernel, `diting_request_match`):
//!
//! ```text
//! | str scheme | str host | str path |
//! ```
//!
//! Match response (kernel -> Go):
//!
//! ```text
//! | i64 matched | i64 blocked | str pattern | str domain host |
//! ```
//!
//! `str` is `u32 length | bytes` (UTF-8 required), every integer is `i64`. A length that disagrees
//! with the payload or trailing bytes is a hard error, never a misread. Nothing here can fail for a
//! well-formed payload: a rule the old code would have dropped is simply not in the set.

use crate::match_rule::{decide, Decision};
use crate::rules::{normalize_all, Rule};

/// Must match `requestPayloadLayoutVersion` in `android/engine/request_native_payload.go`.
pub const LAYOUT_VERSION: u8 = 1;

/// A decoded match request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MatchRequest {
    pub scheme: String,
    pub host: String,
    pub path: String,
}

struct Reader<'a> {
    body: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(body: &'a [u8]) -> Self {
        Self { body, position: 0 }
    }

    fn at_end(&self) -> bool {
        self.position == self.body.len()
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        if length > self.body.len() - self.position {
            return None;
        }
        let slice = &self.body[self.position..self.position + length];
        self.position += length;
        Some(slice)
    }

    fn i64(&mut self) -> Option<i64> {
        let slice = self.take(8)?;
        Some(i64::from_le_bytes(slice.try_into().ok()?))
    }

    fn text(&mut self) -> Option<String> {
        let length = u32::from_le_bytes(self.take(4)?.try_into().ok()?) as usize;
        String::from_utf8(self.take(length)?.to_vec()).ok()
    }

    /// Reads an element count, refusing one the remaining payload cannot hold.
    fn count(&mut self, minimum_bytes: usize) -> Option<usize> {
        let count = self.i64()?;
        if count < 0 {
            return None;
        }
        let count = count as usize;
        if count.saturating_mul(minimum_bytes) > self.body.len() - self.position {
            return None;
        }
        Some(count)
    }
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn put_i64(out: &mut Vec<u8>, value: i64) {
    out.extend_from_slice(&value.to_le_bytes());
}

/// Decodes the rule set payload; `None` means it is malformed.
pub fn decode_rules(payload: &[u8]) -> Option<Vec<(String, String)>> {
    let mut reader = Reader::new(payload);
    let count = reader.count(8)?;
    let mut rules = Vec::with_capacity(count);
    for _ in 0..count {
        let kind = reader.text()?;
        let pattern = reader.text()?;
        rules.push((kind, pattern));
    }
    if !reader.at_end() {
        return None;
    }
    Some(rules)
}

/// Normalizes a decoded rule list. This is the whole `new` operation.
pub fn build_rules(rules: &[(String, String)]) -> Vec<Rule> {
    normalize_all(rules)
}

/// Decodes one match request; `None` means it is malformed.
pub fn decode_match(payload: &[u8]) -> Option<MatchRequest> {
    let mut reader = Reader::new(payload);
    let request = MatchRequest {
        scheme: reader.text()?,
        host: reader.text()?,
        path: reader.text()?,
    };
    if !reader.at_end() {
        return None;
    }
    Some(request)
}

/// Runs the match and encodes the decision.
pub fn encode_match(rules: &[Rule], request: &MatchRequest) -> Vec<u8> {
    let decision = decide(rules, &request.scheme, &request.host, &request.path);
    encode_decision(&decision)
}

fn encode_decision(decision: &Decision) -> Vec<u8> {
    let mut body = Vec::with_capacity(decision.pattern.len() + decision.domain_host.len() + 24);
    put_i64(&mut body, i64::from(decision.matched));
    put_i64(&mut body, i64::from(decision.blocked));
    put_text(&mut body, &decision.pattern);
    put_text(&mut body, &decision.domain_host);
    body
}

#[cfg(test)]
mod tests;

//! The binary layout shared with `android/engine/mitm_cosmetic_native.go`.
//!
//! Little endian, a layout byte first. Five payloads cross the boundary:
//!
//! * `text` — the `<link>` tag the reader splices in, and the normalized page hostname the local
//!   asset server looks rules up with.
//! * `rules` — Go's `encoding/json` decode of the pushed rule set, compiled once per push.
//! * `response` — the local asset server's answer: status, content type, headers, body.
//! * `text list` — the host suffixes, so a fixture can pin the walk.
//!
//! The rewritten response bytes never do — the kernel rewrites the caller's buffer in place, because
//! copying every chunk through a payload would double the work on the hot path.
//!
//! ```text
//! text:      u8 layout | u32 len | bytes
//! text list: u8 layout | u32 count | text × count
//! rules:     u8 layout | u8 state
//!            | [state == 2] u32 n | text × n      (globalHide)
//!                           u32 n | text × n      (globalException)
//!                           u32 nd | (text domain | u32 n | text × n | u32 n | text × n) × nd
//! response:  u8 layout | u16 status | text content_type | u32 n | (text name | text value) × n
//!            | text body
//! ```
//!
//! `state` is `0` empty, `1` invalid, `2` loaded.

use std::collections::HashMap;

use crate::local::Response;
use crate::rules::{DomainRules, RuleSet, Rules};

/// Layout version of the payloads below; `cosmeticPayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

/// `decodedRulesStateEmpty` in Go: the payload was empty or whitespace.
pub const STATE_EMPTY: u8 = 0;
/// `decodedRulesStateInvalid` in Go: `json.Unmarshal` rejected the payload.
pub const STATE_INVALID: u8 = 1;
/// `decodedRulesStateLoaded` in Go: a decoded rule set follows.
pub const STATE_LOADED: u8 = 2;

/// Encodes a string payload: the `<link>` tag or the normalized hostname.
pub fn encode_text(text: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + text.len());
    out.push(LAYOUT_VERSION);
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text);
    out
}

/// Decodes [`encode_text`].
pub fn decode_text(data: &[u8]) -> Result<String, String> {
    let mut reader = Reader::new(data)?;
    let length = reader.u32("text length")? as usize;
    let bytes = reader.bytes(length)?;
    reader.expect_end()?;
    std::str::from_utf8(bytes)
        .map(str::to_string)
        .map_err(|err| format!("payload text is not UTF-8: {err}"))
}

/// Encodes a rule set: Go's decode of one `SetCosmeticRules` payload.
pub fn encode_rules(rules: &RuleSet) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    match rules {
        RuleSet::Empty => out.push(STATE_EMPTY),
        RuleSet::Invalid => out.push(STATE_INVALID),
        RuleSet::Loaded(loaded) => {
            out.push(STATE_LOADED);
            put_texts(&mut out, &loaded.global_hide);
            put_texts(&mut out, &loaded.global_exception);
            // Go sorts the domains so the payload is deterministic; a map has no order of its own.
            let mut domains: Vec<(&String, &DomainRules)> = loaded.domains.iter().collect();
            domains.sort_by(|left, right| left.0.cmp(right.0));
            out.extend_from_slice(&(domains.len() as u32).to_le_bytes());
            for (domain, entry) in domains {
                put_text(&mut out, domain);
                put_texts(&mut out, &entry.hide);
                put_texts(&mut out, &entry.exception);
            }
        }
    }
    out
}

/// Decodes [`encode_rules`].
pub fn decode_rules(data: &[u8]) -> Result<RuleSet, String> {
    let mut reader = Reader::new(data)?;
    let state = reader.u8("rules state")?;
    let rules = match state {
        STATE_EMPTY => RuleSet::Empty,
        STATE_INVALID => RuleSet::Invalid,
        STATE_LOADED => {
            let global_hide = reader.texts("globalHide")?;
            let global_exception = reader.texts("globalException")?;
            let count = reader.u32("domain count")? as usize;
            let mut domains = HashMap::with_capacity(count.min(1024));
            for _ in 0..count {
                let domain = reader.text("domain")?;
                let hide = reader.texts("domain hide")?;
                let exception = reader.texts("domain exception")?;
                // A duplicate domain key keeps the last entry, like `json.Unmarshal` into a map.
                domains.insert(domain, DomainRules { hide, exception });
            }
            RuleSet::Loaded(Rules {
                global_hide,
                global_exception,
                domains,
            })
        }
        other => return Err(format!("unknown rules state {other}")),
    };
    reader.expect_end()?;
    Ok(rules)
}

/// Encodes a host-suffix list.
pub fn encode_text_list(items: &[String]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    put_texts(&mut out, items);
    out
}

/// Decodes [`encode_text_list`].
pub fn decode_text_list(data: &[u8]) -> Result<Vec<String>, String> {
    let mut reader = Reader::new(data)?;
    let items = reader.texts("text list")?;
    reader.expect_end()?;
    Ok(items)
}

/// Encodes one local asset server response.
pub fn encode_response(response: &Response) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&response.status.to_le_bytes());
    put_text(&mut out, response.content_type);
    out.extend_from_slice(&(response.headers.len() as u32).to_le_bytes());
    for (name, value) in &response.headers {
        put_text(&mut out, name);
        put_text(&mut out, value);
    }
    put_text(&mut out, &response.body);
    out
}

/// A decoded [`encode_response`] payload: the body is the interesting part, the headers are copied
/// into `http.Header` verbatim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponsePayload {
    pub status: u16,
    pub content_type: String,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

/// Decodes [`encode_response`].
pub fn decode_response(data: &[u8]) -> Result<ResponsePayload, String> {
    let mut reader = Reader::new(data)?;
    let status = reader.u16("status")?;
    let content_type = reader.text("content type")?;
    let count = reader.u32("header count")? as usize;
    let mut headers = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        let name = reader.text("header name")?;
        let value = reader.text("header value")?;
        headers.push((name, value));
    }
    let body = reader.text("body")?;
    reader.expect_end()?;
    Ok(ResponsePayload {
        status,
        content_type,
        headers,
        body,
    })
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn put_texts(out: &mut Vec<u8>, items: &[String]) {
    out.extend_from_slice(&(items.len() as u32).to_le_bytes());
    for item in items {
        put_text(out, item);
    }
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Result<Self, String> {
        let mut reader = Reader { data, pos: 0 };
        reader.layout()?;
        Ok(reader)
    }

    fn remaining(&self) -> usize {
        self.data.len() - self.pos
    }

    fn layout(&mut self) -> Result<u8, String> {
        if self.remaining() < 1 {
            return Err("payload is truncated (layout)".to_string());
        }
        let layout = self.data[self.pos];
        self.pos += 1;
        if layout != LAYOUT_VERSION {
            return Err(format!("layout {layout}, expected {LAYOUT_VERSION}"));
        }
        Ok(layout)
    }

    fn u8(&mut self, what: &str) -> Result<u8, String> {
        if self.remaining() < 1 {
            return Err(format!("payload is truncated ({what})"));
        }
        let value = self.data[self.pos];
        self.pos += 1;
        Ok(value)
    }

    fn u16(&mut self, what: &str) -> Result<u16, String> {
        if self.remaining() < 2 {
            return Err(format!("payload is truncated ({what})"));
        }
        let mut bytes = [0u8; 2];
        bytes.copy_from_slice(&self.data[self.pos..self.pos + 2]);
        self.pos += 2;
        Ok(u16::from_le_bytes(bytes))
    }

    fn text(&mut self, what: &str) -> Result<String, String> {
        let length = self.u32(what)? as usize;
        let bytes = self.bytes(length)?;
        std::str::from_utf8(bytes)
            .map(str::to_string)
            .map_err(|err| format!("payload {what} is not UTF-8: {err}"))
    }

    fn texts(&mut self, what: &str) -> Result<Vec<String>, String> {
        let count = self.u32(what)? as usize;
        let mut items = Vec::with_capacity(count.min(1024));
        for _ in 0..count {
            items.push(self.text(what)?);
        }
        Ok(items)
    }

    fn u32(&mut self, what: &str) -> Result<u32, String> {
        if self.remaining() < 4 {
            return Err(format!("payload is truncated ({what})"));
        }
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&self.data[self.pos..self.pos + 4]);
        self.pos += 4;
        Ok(u32::from_le_bytes(bytes))
    }

    fn bytes(&mut self, length: usize) -> Result<&'a [u8], String> {
        if self.remaining() < length {
            return Err("payload is truncated (bytes)".to_string());
        }
        let value = &self.data[self.pos..self.pos + length];
        self.pos += length;
        Ok(value)
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

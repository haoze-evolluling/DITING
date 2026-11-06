//! The compact binary layout shared with the Go side (`desktop/service/internal/core/filter_native.go`).
//!
//! Everything is little endian, strings are `u16`-length prefixed, and every payload starts with a
//! layout byte so a mismatched Go/Rust pair is a loud error instead of a misread field. The rule
//! payload carries only what a decision needs: Go keeps the rule text, the list name and the
//! `$dnsrewrite` record construction.

use std::fmt;

use diting_go_compat::regex::compile_rule_regex;

use crate::index::{Action, Decision, FilterIndex};
use crate::rule::{RewriteAction, Rule, KNOWN_FLAGS};

pub const LAYOUT_VERSION: u8 = 1;

/// `NO_REASON` in a decision payload.
pub const NO_CODE: u8 = 0xFF;
/// `NO_RULE` in a decision payload.
pub const NO_INDEX: u32 = u32::MAX;

/// Why a payload could not be decoded; the message is surfaced to the Go caller.
#[derive(Debug)]
pub struct DecodeError(pub String);

impl fmt::Display for DecodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl DecodeError {
    fn truncated(field: &str) -> Self {
        Self(format!("rules payload is truncated ({field})"))
    }

    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

pub(crate) struct Reader<'a> {
    data: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    pub(crate) fn new(data: &'a [u8]) -> Self {
        Self { data, position: 0 }
    }

    pub(crate) fn remaining(&self) -> usize {
        self.data.len() - self.position
    }

    pub(crate) fn u8(&mut self, field: &str) -> Result<u8, DecodeError> {
        if self.remaining() < 1 {
            return Err(DecodeError::truncated(field));
        }
        let value = self.data[self.position];
        self.position += 1;
        Ok(value)
    }

    pub(crate) fn u16(&mut self, field: &str) -> Result<u16, DecodeError> {
        if self.remaining() < 2 {
            return Err(DecodeError::truncated(field));
        }
        let value = u16::from_le_bytes([self.data[self.position], self.data[self.position + 1]]);
        self.position += 2;
        Ok(value)
    }

    pub(crate) fn u32(&mut self, field: &str) -> Result<u32, DecodeError> {
        if self.remaining() < 4 {
            return Err(DecodeError::truncated(field));
        }
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&self.data[self.position..self.position + 4]);
        self.position += 4;
        Ok(u32::from_le_bytes(bytes))
    }

    pub(crate) fn text(&mut self, field: &str) -> Result<String, DecodeError> {
        let length = self.u16(field)? as usize;
        if self.remaining() < length {
            return Err(DecodeError::truncated(field));
        }
        let slice = &self.data[self.position..self.position + length];
        self.position += length;
        String::from_utf8(slice.to_vec())
            .map_err(|_| DecodeError::invalid(format!("{field} is not valid UTF-8")))
    }

    fn texts(&mut self, field: &str) -> Result<Vec<String>, DecodeError> {
        let count = self.u16(field)? as usize;
        let mut out = Vec::with_capacity(count);
        for _ in 0..count {
            out.push(self.text(field)?);
        }
        Ok(out)
    }

    /// Long text: `u32` length, for payloads that carry whole documents (the parser request).
    pub(crate) fn text32(&mut self, field: &str) -> Result<String, DecodeError> {
        let slice = self.bytes32(field)?;
        String::from_utf8(slice.to_vec())
            .map_err(|_| DecodeError::invalid(format!("{field} is not valid UTF-8")))
    }

    /// Long bytes: `u32` length, no encoding requirement.
    pub(crate) fn bytes32(&mut self, field: &str) -> Result<&'a [u8], DecodeError> {
        let length = self.u32(field)? as usize;
        if self.remaining() < length {
            return Err(DecodeError::truncated(field));
        }
        let slice = &self.data[self.position..self.position + length];
        self.position += length;
        Ok(slice)
    }

    pub(crate) fn expect_end(&self) -> Result<(), DecodeError> {
        if self.remaining() == 0 {
            Ok(())
        } else {
            Err(DecodeError::invalid(format!(
                "rules payload has {} trailing bytes",
                self.remaining()
            )))
        }
    }
}

/// Decodes the rule payload Go builds from its parsed rules.
pub fn decode_rules(data: &[u8]) -> Result<Vec<Rule>, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "rules payload layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let count = reader.u32("rule count")? as usize;
    let mut rules = Vec::with_capacity(count.min(1 << 16));
    for _ in 0..count {
        rules.push(decode_rule(&mut reader)?);
    }
    reader.expect_end()?;
    Ok(rules)
}

fn decode_rule(reader: &mut Reader<'_>) -> Result<Rule, DecodeError> {
    let flags = reader.u8("rule flags")?;
    if flags & !KNOWN_FLAGS != 0 {
        return Err(DecodeError::invalid(format!(
            "rule flags {:08b} contain unknown bits",
            flags
        )));
    }
    let dns_type = reader.u16("rule dnstype")?;
    let pattern = reader.text("rule pattern")?;
    if pattern.is_empty() {
        return Err(DecodeError::invalid("rule pattern is empty".to_string()));
    }
    let regex_source = reader.text("rule regex")?;
    let mut rule = Rule::new(pattern).with_flags(flags).with_dns_type(dns_type);
    rule.deny_allow = reader.texts("rule denyallow")?;
    rule.to = reader.texts("rule to")?;
    if !regex_source.is_empty() {
        // `None` means the pattern never matches; Go logs a count of these at build time.
        rule.regex = compile_rule_regex(&regex_source).ok();
    }
    if rule.has_rewrite() {
        let bare = reader.u8("rewrite bare")? != 0;
        let rcode = reader.u8("rewrite rcode")?;
        let rrtype = reader.u16("rewrite rrtype")?;
        let key = reader.text("rewrite key")?;
        rule.rewrite = Some(RewriteAction {
            bare,
            rcode,
            rrtype,
            key,
        });
    }
    Ok(rule)
}

/// Encodes one decision for the Go caller.
pub fn encode_decision(decision: &Decision) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION, decision.action.code()];
    out.push(decision.reason.map_or(NO_CODE, |reason| reason.code()));
    out.extend_from_slice(&decision.rule.unwrap_or(NO_INDEX).to_le_bytes());
    match &decision.rewrite {
        Some(answer) => {
            out.push(1);
            out.push(answer.rcode);
            out.extend_from_slice(&(answer.rules.len() as u32).to_le_bytes());
            for rule in &answer.rules {
                out.extend_from_slice(&rule.to_le_bytes());
            }
        }
        None => out.push(0),
    }
    out
}

/// Encodes the build report Go needs after an index is built.
pub fn encode_stats(index: &FilterIndex) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&index.total_rules().to_le_bytes());
    out.push(u8::from(index.has_deny_allow()));
    out.extend_from_slice(&index.uncompiled_patterns().to_le_bytes());
    out
}

impl Action {
    /// Stable code for the decision payload; Go maps it back to its action strings.
    pub fn code(self) -> u8 {
        match self {
            Action::Pass => 0,
            Action::Allow => 1,
            Action::Block => 2,
            Action::Rewrite => 3,
        }
    }
}

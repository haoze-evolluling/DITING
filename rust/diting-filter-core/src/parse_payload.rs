//! The compact binary layout the parser entry points share with Go
//! (`desktop/service/internal/core/parse_native.go`).
//!
//! Two payloads, both little endian, both starting with their own layout byte so a mismatched
//! Go/Rust pair is a loud rejection instead of a misread field:
//!
//! * request: the text to parse (one line or a whole document);
//! * reply: the parsed lines, in list order.
//!
//! Text lengths are `u32` here, not the `u16` the matcher payload uses: a single list can be a few
//! megabytes and one regex rule can be a kilobyte, so the narrow length would be a truncation
//! waiting to happen. The parser runs once per list load, never per query.

use std::borrow::Cow;

use crate::parse::ParsedLine;
use crate::payload::{DecodeError, Reader};
use crate::rule::{
    FLAG_ALLOW, FLAG_EXACT, FLAG_IMPORTANT, FLAG_REGEX, FLAG_REWRITE, FLAG_WILDCARD,
};

/// Layout version of both payloads below; `parseNativeLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

/// Decodes a parser request into the text to parse. The list name stays in Go: it is a label the
/// parser never looks at.
///
/// The text is decoded lossily on purpose. Filter lists are plain files from the internet and are
/// not always UTF-8; Go strings could carry such bytes through (its `strings.ToLower` turns them
/// into U+FFFD, which IDNA then rejects), so the port does the same instead of failing the whole
/// list over one bad byte.
pub fn decode_request(data: &[u8]) -> Result<Cow<'_, str>, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "parse request layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let text = reader.bytes32("parse text")?;
    reader.expect_end()?;
    Ok(String::from_utf8_lossy(text))
}

/// Encodes the reply: one record per parsed line.
pub fn encode_parsed_lines(lines: &[ParsedLine]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(lines.len() as u32).to_le_bytes());
    for line in lines {
        push_text(&mut out, &line.raw);
        push_text(&mut out, &line.pattern);
        out.push(flags_of(line));
        out.extend_from_slice(&line.dns_type.to_le_bytes());
        push_texts(&mut out, &line.deny_allow);
        push_texts(&mut out, &line.to);
        if let Some(value) = &line.rewrite {
            push_text(&mut out, value);
        }
    }
    out
}

/// Decodes a reply back into lines; only the tests need it, Go reads the same bytes field by field.
pub fn decode_parsed_lines(data: &[u8]) -> Result<Vec<ParsedLine>, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "parse reply layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let count = reader.u32("parse rule count")? as usize;
    let mut lines = Vec::with_capacity(count.min(1 << 16));
    for _ in 0..count {
        let raw = reader.text32("rule raw")?;
        let pattern = reader.text32("rule pattern")?;
        let flags = reader.u8("rule flags")?;
        let dns_type = reader.u16("rule dnstype")?;
        let deny_allow = read_texts(&mut reader, "rule denyallow")?;
        let to = read_texts(&mut reader, "rule to")?;
        let rewrite = if flags & FLAG_REWRITE != 0 {
            Some(reader.text32("rewrite value")?)
        } else {
            None
        };
        lines.push(ParsedLine {
            raw,
            pattern,
            is_allow: flags & FLAG_ALLOW != 0,
            important: flags & FLAG_IMPORTANT != 0,
            is_regex: flags & FLAG_REGEX != 0,
            dns_type,
            is_wildcard: flags & FLAG_WILDCARD != 0,
            is_exact: flags & FLAG_EXACT != 0,
            deny_allow,
            to,
            rewrite,
        });
    }
    reader.expect_end()?;
    Ok(lines)
}

/// Packs the booleans, using the matcher's flag bits so Go has one table, not two.
fn flags_of(line: &ParsedLine) -> u8 {
    let mut flags = 0u8;
    if line.is_allow {
        flags |= FLAG_ALLOW;
    }
    if line.important {
        flags |= FLAG_IMPORTANT;
    }
    if line.is_regex {
        flags |= FLAG_REGEX;
    }
    if line.is_wildcard {
        flags |= FLAG_WILDCARD;
    }
    if line.is_exact {
        flags |= FLAG_EXACT;
    }
    if line.rewrite.is_some() {
        flags |= FLAG_REWRITE;
    }
    flags
}

fn push_text(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(&(value.len() as u32).to_le_bytes());
    out.extend_from_slice(value.as_bytes());
}

fn push_texts(out: &mut Vec<u8>, values: &[String]) {
    out.extend_from_slice(&(values.len() as u16).to_le_bytes());
    for value in values {
        push_text(out, value);
    }
}

fn read_texts(reader: &mut Reader<'_>, field: &str) -> Result<Vec<String>, DecodeError> {
    let count = reader.u16(field)? as usize;
    let mut out = Vec::with_capacity(count);
    for _ in 0..count {
        out.push(reader.text32(field)?);
    }
    Ok(out)
}

use std::borrow::Cow;

use crate::parse::ParsedLine;
use crate::payload::{DecodeError, Reader};
use crate::rule::{
    FLAG_ALLOW, FLAG_EXACT, FLAG_IMPORTANT, FLAG_REGEX, FLAG_REWRITE, FLAG_WILDCARD,
};

pub const LAYOUT_VERSION: u8 = 1;

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

use std::path::PathBuf;

use crate::arpa::parse_arpa;
use crate::hosts::Source;
use crate::ip::Addr;

pub const LAYOUT_VERSION: u8 = 1;

const SOURCE_FILE: u8 = 0;
const SOURCE_TEXT: u8 = 1;

pub fn encode_sources(sources: &[Source]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5);
    out.push(LAYOUT_VERSION);
    push_u32(&mut out, sources.len() as u32);
    for source in sources {
        match source {
            Source::File(path) => {
                out.push(SOURCE_FILE);
                push_text(&mut out, &path.display().to_string());
            }
            Source::Text(text) => {
                out.push(SOURCE_TEXT);
                push_text(&mut out, text);
            }
        }
    }
    out
}

pub fn decode_sources(data: &[u8]) -> Result<Vec<Source>, String> {
    let mut reader = Reader::new(data);
    reader.layout("sources")?;
    let count = reader.u32("source count")? as usize;
    let mut sources = Vec::with_capacity(count);
    for _ in 0..count {
        let kind = reader.u8("source kind")?;
        let text = reader.text()?;
        sources.push(match kind {
            SOURCE_FILE => Source::File(PathBuf::from(text)),
            SOURCE_TEXT => Source::Text(text),
            other => return Err(format!("unknown source kind {other}")),
        });
    }
    reader.expect_end()?;
    Ok(sources)
}

pub fn encode_info(loaded: &[String], error: Option<&str>) -> Vec<u8> {
    let mut out = Vec::with_capacity(9);
    out.push(LAYOUT_VERSION);
    out.push(u8::from(error.is_some()));
    push_text(&mut out, error.unwrap_or(""));
    push_u32(&mut out, loaded.len() as u32);
    for path in loaded {
        push_text(&mut out, path);
    }
    out
}

pub fn encode_lookup(addresses: &[Addr]) -> Vec<u8> {
    let width = addresses.first().map(Addr::width).unwrap_or(4);
    let mut out = Vec::with_capacity(6 + addresses.len() * width);
    out.push(LAYOUT_VERSION);
    out.push(width as u8);
    push_u32(&mut out, addresses.len() as u32);
    for address in addresses {
        out.extend_from_slice(address.as_bytes());
    }
    out
}

pub fn encode_names(names: &[String]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5);
    out.push(LAYOUT_VERSION);
    push_u32(&mut out, names.len() as u32);
    for name in names {
        push_text(&mut out, name);
    }
    out
}

pub fn encode_reverse(name: Option<&str>) -> Vec<u8> {
    let mut out = Vec::with_capacity(6);
    out.push(LAYOUT_VERSION);
    out.push(u8::from(name.is_some()));
    push_text(&mut out, name.unwrap_or(""));
    out
}

pub fn encode_arpa(addr: Option<Addr>) -> Vec<u8> {
    let mut out = Vec::with_capacity(6);
    out.push(LAYOUT_VERSION);
    match addr {
        Some(addr) => {
            out.push(addr.width() as u8);
            out.extend_from_slice(addr.as_bytes());
        }
        None => out.push(0),
    }
    out
}

pub fn encode_arpa_name(name: &str) -> Vec<u8> {
    encode_arpa(parse_arpa(name))
}

fn push_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn push_text(out: &mut Vec<u8>, text: &str) {
    push_u32(out, text.len() as u32);
    out.extend_from_slice(text.as_bytes());
}

pub(crate) struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub(crate) fn new(data: &'a [u8]) -> Self {
        Reader { data, pos: 0 }
    }

    pub(crate) fn remaining(&self) -> usize {
        self.data.len() - self.pos
    }

    pub(crate) fn u8(&mut self, what: &str) -> Result<u8, String> {
        if self.remaining() < 1 {
            return Err(format!("payload is truncated ({what})"));
        }
        let value = self.data[self.pos];
        self.pos += 1;
        Ok(value)
    }

    pub(crate) fn layout(&mut self, what: &str) -> Result<u8, String> {
        let layout = self.u8(what)?;
        if layout != LAYOUT_VERSION {
            return Err(format!("{what} layout {layout}, expected {LAYOUT_VERSION}"));
        }
        Ok(layout)
    }

    pub(crate) fn u32(&mut self, what: &str) -> Result<u32, String> {
        if self.remaining() < 4 {
            return Err(format!("payload is truncated ({what})"));
        }
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&self.data[self.pos..self.pos + 4]);
        self.pos += 4;
        Ok(u32::from_le_bytes(bytes))
    }

    pub(crate) fn text(&mut self) -> Result<String, String> {
        let length = self.u32("text length")? as usize;
        if self.remaining() < length {
            return Err("payload is truncated (text)".to_string());
        }
        let text = std::str::from_utf8(&self.data[self.pos..self.pos + length])
            .map_err(|err| format!("payload text is not UTF-8: {err}"))?;
        self.pos += length;
        Ok(text.to_string())
    }

    #[cfg(test)]
    pub(crate) fn bytes(&mut self, length: usize, what: &str) -> Result<&'a [u8], String> {
        if self.remaining() < length {
            return Err(format!("payload is truncated ({what})"));
        }
        let value = &self.data[self.pos..self.pos + length];
        self.pos += length;
        Ok(value)
    }

    pub(crate) fn expect_end(&self) -> Result<(), String> {
        if self.remaining() != 0 {
            return Err(format!("payload has {} trailing bytes", self.remaining()));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests;

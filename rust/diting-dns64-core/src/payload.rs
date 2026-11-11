//! The binary layouts shared with `desktop/service/internal/core/dns64_native.go`.
//!
//! Little endian, a layout byte first. Addresses travel as a one-byte width plus that many bytes,
//! which is exactly how Go hands them over: 4 bytes for `IP.To4()`, 16 bytes for a parsed IPv6
//! address, 0 for a nil one.
//!
//! ```text
//! new:       u8 layout | u16 count | (u32 len | text) * count
//! addresses: u8 layout | u16 count | (u8 width | bytes) * count
//! result:    u8 layout | u8 count | 16-byte address * count
//! ```

/// Layout version of every payload below; `dns64PayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

/// The widest address the layouts carry; anything longer is a corrupt payload.
const MAX_WIDTH: usize = 16;

/// Encodes the configured prefix list.
pub fn encode_prefixes(prefixes: &[String]) -> Vec<u8> {
    let mut out = Vec::with_capacity(3);
    out.push(LAYOUT_VERSION);
    push_u16(&mut out, prefixes.len() as u16);
    for prefix in prefixes {
        push_text(&mut out, prefix);
    }
    out
}

/// Decodes [`encode_prefixes`]: this is how `diting_dns64_new` reads its argument.
pub fn decode_prefixes(data: &[u8]) -> Result<Vec<String>, String> {
    let mut reader = Reader::new(data);
    reader.layout("prefixes")?;
    let count = usize::from(reader.u16("prefix count")?);
    let mut prefixes = Vec::with_capacity(count);
    for _ in 0..count {
        prefixes.push(reader.text()?);
    }
    reader.expect_end()?;
    Ok(prefixes)
}

/// Encodes an address list for the AAAA check.
pub fn encode_addresses(addresses: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::with_capacity(3 + addresses.len() * 17);
    out.push(LAYOUT_VERSION);
    push_u16(&mut out, addresses.len() as u16);
    for address in addresses {
        out.push(address.len() as u8);
        out.extend_from_slice(address);
    }
    out
}

/// Decodes [`encode_addresses`].
pub fn decode_addresses(data: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    let mut reader = Reader::new(data);
    reader.layout("addresses")?;
    let count = usize::from(reader.u16("address count")?);
    let mut addresses = Vec::with_capacity(count);
    for _ in 0..count {
        let width = usize::from(reader.u8("address width")?);
        if width > MAX_WIDTH {
            return Err(format!("address width {width} exceeds {MAX_WIDTH}"));
        }
        addresses.push(reader.bytes(width)?.to_vec());
    }
    reader.expect_end()?;
    Ok(addresses)
}

/// Encodes synthesized addresses for Go to wrap in `dns.AAAA`.
pub fn encode_result(addresses: &[[u8; 16]]) -> Vec<u8> {
    let mut out = Vec::with_capacity(2 + addresses.len() * 16);
    out.push(LAYOUT_VERSION);
    out.push(addresses.len() as u8);
    for address in addresses {
        out.extend_from_slice(address);
    }
    out
}

fn push_u16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn push_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
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

    fn remaining(&self) -> usize {
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

    pub(crate) fn u16(&mut self, what: &str) -> Result<u16, String> {
        if self.remaining() < 2 {
            return Err(format!("payload is truncated ({what})"));
        }
        let mut bytes = [0u8; 2];
        bytes.copy_from_slice(&self.data[self.pos..self.pos + 2]);
        self.pos += 2;
        Ok(u16::from_le_bytes(bytes))
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
        let bytes = self.bytes(length)?;
        std::str::from_utf8(bytes)
            .map(str::to_string)
            .map_err(|err| format!("payload text is not UTF-8: {err}"))
    }

    pub(crate) fn bytes(&mut self, length: usize) -> Result<&'a [u8], String> {
        if self.remaining() < length {
            return Err("payload is truncated (bytes)".to_string());
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

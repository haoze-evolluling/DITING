//! The binary layout shared with `android/engine/mitm_cosmetic_native.go`.
//!
//! Little endian, a layout byte first. Two payloads cross the boundary, both plain text: the `<link>`
//! tag the reader splices in, and the normalized page hostname the local asset server looks rules up
//! with. The response bytes never do — the kernel rewrites the caller's buffer in place, because
//! copying every chunk through a payload would double the work on the hot path.
//!
//! ```text
//! text: u8 layout | u32 len | bytes
//! ```

/// Layout version of the payload below; `cosmeticPayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

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
    let mut reader = Reader::new(data);
    reader.layout()?;
    let length = reader.u32("text length")? as usize;
    let bytes = reader.bytes(length)?;
    reader.expect_end()?;
    std::str::from_utf8(bytes)
        .map(str::to_string)
        .map_err(|err| format!("payload text is not UTF-8: {err}"))
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Reader { data, pos: 0 }
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

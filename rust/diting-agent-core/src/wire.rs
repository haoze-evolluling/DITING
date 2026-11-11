//! Fixed-layout payload reader/writer for the `dart:ffi` boundary.
//!
//! Little-endian, matching the Dart side (`ByteData.getUint32(..., Endian.little)`). Strings are a
//! `u32` byte length plus UTF-8; optional strings use `u32::MAX` as the absent marker, so a payload
//! never needs a separate presence bit.

pub const NONE: u32 = u32::MAX;

pub struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Self {
            bytes: Vec::with_capacity(64),
        }
    }

    pub fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    pub fn u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn f64(&mut self, value: f64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn string(&mut self, value: &str) {
        self.u32(value.len() as u32);
        self.bytes.extend_from_slice(value.as_bytes());
    }

    pub fn opt_string(&mut self, value: Option<&str>) {
        match value {
            Some(text) => self.string(text),
            None => self.u32(NONE),
        }
    }

    pub fn finish(self) -> Vec<u8> {
        self.bytes
    }
}

impl Default for Writer {
    fn default() -> Self {
        Self::new()
    }
}

pub struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn take(&mut self, count: usize) -> Option<&'a [u8]> {
        let end = self.offset.checked_add(count)?;
        if end > self.bytes.len() {
            return None;
        }
        let slice = &self.bytes[self.offset..end];
        self.offset = end;
        Some(slice)
    }

    pub fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    pub fn u32(&mut self) -> Option<u32> {
        let raw = self.take(4)?;
        Some(u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]))
    }

    pub fn f64(&mut self) -> Option<f64> {
        let raw = self.take(8)?;
        let mut fixed = [0u8; 8];
        fixed.copy_from_slice(raw);
        Some(f64::from_le_bytes(fixed))
    }

    pub fn string(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        if length as u32 == NONE {
            return None;
        }
        let raw = self.take(length)?;
        String::from_utf8(raw.to_vec()).ok()
    }

    pub fn opt_string(&mut self) -> Option<Option<String>> {
        let length = self.u32()?;
        if length == NONE {
            return Some(None);
        }
        let raw = self.take(length as usize)?;
        Some(Some(String::from_utf8(raw.to_vec()).ok()?))
    }
}

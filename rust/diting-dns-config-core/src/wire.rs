//! Fixed-layout payload reader/writer for the `dart:ffi` boundary.
//!
//! Little-endian, matching the Dart side. Strings are a `u32` byte length plus UTF-8; optional
//! strings use `u32::MAX` as the absent marker, so a payload never needs a separate presence bit.

pub const NONE: u32 = u32::MAX;

pub struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Self {
            bytes: Vec::with_capacity(256),
        }
    }

    pub fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    pub fn bool(&mut self, value: bool) {
        self.u8(u8::from(value));
    }

    pub fn u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn i32(&mut self, value: i32) {
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

    pub fn strings(&mut self, values: &[String]) {
        self.u32(values.len() as u32);
        for value in values {
            self.string(value);
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

    pub fn bool(&mut self) -> Option<bool> {
        Some(self.u8()? != 0)
    }

    pub fn u32(&mut self) -> Option<u32> {
        let raw = self.take(4)?;
        Some(u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]))
    }

    pub fn i32(&mut self) -> Option<i32> {
        let raw = self.take(4)?;
        Some(i32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]))
    }

    pub fn string(&mut self) -> Option<String> {
        let length = self.u32()?;
        if length == NONE {
            return None;
        }
        let raw = self.take(length as usize)?;
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

    pub fn strings(&mut self) -> Option<Vec<String>> {
        let count = self.u32()?;
        let mut items = Vec::with_capacity(count.min(4096) as usize);
        for _ in 0..count {
            items.push(self.string()?);
        }
        Some(items)
    }
}

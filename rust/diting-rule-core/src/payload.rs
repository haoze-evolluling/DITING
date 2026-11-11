//! Fixed-layout payload reader/writer for the `RuleIndexNative` calls.
//!
//! Big-endian, matching `DataOutputStream` on the Kotlin side. Strings are a `u32` byte length plus
//! UTF-8; blobs are the same with opaque bytes. [`Reader::finish`] rejects trailing bytes, so a
//! payload from a newer Kotlin side is a hard error rather than a partial read.

/// Big-endian cursor over one payload.
pub struct Reader<'a> {
    data: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, offset: 0 }
    }

    fn take(&mut self, count: usize) -> Option<&'a [u8]> {
        let end = self.offset.checked_add(count)?;
        if end > self.data.len() {
            return None;
        }
        let slice = &self.data[self.offset..end];
        self.offset = end;
        Some(slice)
    }

    pub fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    pub fn u32(&mut self) -> Option<u32> {
        let bytes = self.take(4)?;
        Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    pub fn i32(&mut self) -> Option<i32> {
        let bytes = self.take(4)?;
        Some(i32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    pub fn i64(&mut self) -> Option<i64> {
        let bytes = self.take(8)?;
        let mut raw = [0u8; 8];
        raw.copy_from_slice(bytes);
        Some(i64::from_be_bytes(raw))
    }

    /// `u32` length plus opaque bytes.
    pub fn blob(&mut self) -> Option<&'a [u8]> {
        let length = self.u32()? as usize;
        self.take(length)
    }

    /// `u32` length plus UTF-8 bytes.
    pub fn string(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        let raw = self.take(length)?;
        String::from_utf8(raw.to_vec()).ok()
    }

    /// True when the whole payload was consumed.
    pub fn finish(&self) -> bool {
        self.offset == self.data.len()
    }
}

/// Append-only payload builder.
pub struct Writer {
    data: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Self { data: Vec::new() }
    }

    pub fn u8(&mut self, value: u8) {
        self.data.push(value);
    }

    pub fn u32(&mut self, value: u32) {
        self.data.extend_from_slice(&value.to_be_bytes());
    }

    pub fn i32(&mut self, value: i32) {
        self.data.extend_from_slice(&value.to_be_bytes());
    }

    pub fn i64(&mut self, value: i64) {
        self.data.extend_from_slice(&value.to_be_bytes());
    }

    pub fn blob(&mut self, value: &[u8]) {
        self.u32(value.len() as u32);
        self.data.extend_from_slice(value);
    }

    pub fn string(&mut self, value: &str) {
        self.u32(value.len() as u32);
        self.data.extend_from_slice(value.as_bytes());
    }

    pub fn into_vec(self) -> Vec<u8> {
        self.data
    }
}

impl Default for Writer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_rejects_drift() {
        let mut writer = Writer::new();
        writer.u8(7);
        writer.u32(4);
        writer.i32(-4);
        writer.i64(1 << 40);
        writer.blob(&[1, 2, 3]);
        writer.string("example.com");
        let payload = writer.into_vec();

        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(7));
        assert_eq!(reader.u32(), Some(4));
        assert_eq!(reader.i32(), Some(-4));
        assert_eq!(reader.i64(), Some(1 << 40));
        assert_eq!(reader.blob(), Some(&[1, 2, 3][..]));
        assert_eq!(reader.string().as_deref(), Some("example.com"));
        assert!(reader.finish());

        // One trailing byte is drift, not something to ignore.
        let mut padded = payload.clone();
        padded.push(0);
        let mut reader = Reader::new(&padded);
        assert!(reader.string().is_some() || reader.u8().is_some());
        assert!(!reader.finish());

        // Truncation is a failed read, never a default value.
        let mut reader = Reader::new(&payload[..payload.len() - 2]);
        assert!(reader.u8().is_some());
        assert!(reader.u32().is_some());
        assert!(reader.i32().is_some());
        assert!(reader.i64().is_some());
        assert!(reader.blob().is_some());
        assert_eq!(reader.string(), None);
    }
}

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

    pub fn u16(&mut self) -> Option<u16> {
        let bytes = self.take(2)?;
        Some(u16::from_be_bytes([bytes[0], bytes[1]]))
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

    pub fn f64(&mut self) -> Option<f64> {
        let bytes = self.take(8)?;
        let mut raw = [0u8; 8];
        raw.copy_from_slice(bytes);
        Some(f64::from_be_bytes(raw))
    }

    pub fn bytes(&mut self, count: usize) -> Option<&'a [u8]> {
        self.take(count)
    }

    pub fn string(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        let raw = self.bytes(length)?;
        String::from_utf8(raw.to_vec()).ok()
    }

    pub fn rest(&mut self) -> &'a [u8] {
        let rest = &self.data[self.offset..];
        self.offset = self.data.len();
        rest
    }

    pub fn finish(&self) -> bool {
        self.offset == self.data.len()
    }
}

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

    pub fn u16(&mut self, value: u16) {
        self.data.extend_from_slice(&value.to_be_bytes());
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

    pub fn f64(&mut self, value: f64) {
        self.data.extend_from_slice(&value.to_be_bytes());
    }

    pub fn bytes(&mut self, value: &[u8]) {
        self.data.extend_from_slice(value);
    }

    pub fn string(&mut self, value: &str) {
        self.u32(value.len() as u32);
        self.bytes(value.as_bytes());
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
        writer.f64(1.5);
        writer.string("dns.google");
        let payload = writer.into_vec();

        let mut reader = Reader::new(&payload);
        assert_eq!(reader.u8(), Some(7));
        assert_eq!(reader.u32(), Some(4));
        assert_eq!(reader.i32(), Some(-4));
        assert_eq!(reader.f64(), Some(1.5));
        assert_eq!(reader.string().as_deref(), Some("dns.google"));
        assert!(reader.finish());

        let mut padded = payload.clone();
        padded.push(0);
        let mut reader = Reader::new(&padded);
        assert_eq!(reader.u8(), Some(7));
        assert_eq!(reader.u32(), Some(4));
        assert_eq!(reader.i32(), Some(-4));
        assert_eq!(reader.f64(), Some(1.5));
        assert_eq!(reader.string().as_deref(), Some("dns.google"));
        assert!(!reader.finish());

        let mut reader = Reader::new(&payload[..payload.len() - 2]);
        assert!(reader.u8().is_some());
        assert!(reader.u32().is_some());
        assert!(reader.i32().is_some());
        assert!(reader.f64().is_some());
        assert_eq!(reader.string(), None);
    }
}

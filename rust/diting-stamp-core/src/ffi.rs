//! C ABI surface and the payload the Go side decodes.
//!
//! One call per stamp: parsing happens when a provider is configured or a stamp is pasted into the
//! editor, never on the query path, so the boundary cost does not matter and the whole record can
//! cross in one buffer.
//!
//! Wire format of the returned buffer (little-endian, strings are `u16 len` + UTF-8 bytes):
//!
//! ```text
//! u8  layout version (1) | u8 proto id | u64 props
//! str protocol | str server_addr | str provider_name | str path | str url | str server
//! u16 pin count    | pin count × 32 bytes
//! u16 bootstrap count | bootstrap count × str
//! ```
//!
//! `diting_stamp_parse` returns a status: `0` means the payload is a record, `1` means the payload
//! is the rejection message (same bytes the Go parser used to return as `error`), `2` means the
//! arguments were unusable. The caller owns the buffer either way and releases it with
//! [`diting_stamp_free`].

use crate::stamp::{self, Stamp};

/// Bumped whenever the payload layout or the parsing semantics change; the Go loader refuses a
/// library whose value does not match what it was compiled against.
pub const ABI_VERSION: u32 = 1;

/// Payload layout version, written as the first byte so the Go decoder can reject a mismatch.
pub const PAYLOAD_LAYOUT_VERSION: u8 = 1;

pub const STATUS_OK: u32 = 0;
pub const STATUS_REJECTED: u32 = 1;
pub const STATUS_INVALID_ARGUMENT: u32 = 2;

fn write_u16(buffer: &mut Vec<u8>, value: usize) {
    buffer.extend_from_slice(&(value as u16).to_le_bytes());
}

fn write_str(buffer: &mut Vec<u8>, value: &str) {
    write_u16(buffer, value.len());
    buffer.extend_from_slice(value.as_bytes());
}

fn encode_stamp(stamp_record: &Stamp) -> Vec<u8> {
    let mut buffer = Vec::with_capacity(256);
    buffer.push(PAYLOAD_LAYOUT_VERSION);
    buffer.push(stamp_record.proto.code());
    buffer.extend_from_slice(&stamp_record.props.to_le_bytes());
    write_str(&mut buffer, stamp_record.proto.protocol());
    write_str(&mut buffer, &stamp_record.server_addr);
    write_str(&mut buffer, &stamp_record.provider_name);
    write_str(&mut buffer, &stamp_record.path);
    write_str(&mut buffer, &stamp_record.url());
    write_str(&mut buffer, &stamp_record.server());
    write_u16(&mut buffer, stamp_record.hashes.len());
    for hash in &stamp_record.hashes {
        buffer.extend_from_slice(hash);
    }
    write_u16(&mut buffer, stamp_record.bootstrap_ips.len());
    for ip in &stamp_record.bootstrap_ips {
        write_str(&mut buffer, ip);
    }
    buffer
}

/// Hands `bytes` to the caller as a pointer/length pair [`diting_stamp_free`] can rebuild.
fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

/// Payload layout version, so the Go loader can tell a stale artifact from a fresh one.
#[no_mangle]
pub extern "C" fn diting_stamp_abi_version() -> u32 {
    ABI_VERSION
}

/// Parses `len` UTF-8 bytes at `input` and returns a buffer the caller must release with
/// [`diting_stamp_free`]. `out_ptr`/`out_len` receive the buffer; the return value is one of the
/// `STATUS_*` codes.
///
/// # Safety
/// `input` must point to `len` readable bytes when `len` is non-zero, and both out parameters
/// must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_stamp_parse(
    input: *const u8,
    len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> u32 {
    if out_ptr.is_null() || out_len.is_null() {
        return STATUS_INVALID_ARGUMENT;
    }
    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let bytes: &[u8] = if input.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(input, len)
    };
    let (status, payload) = match std::str::from_utf8(bytes) {
        Ok(text) => match stamp::parse(text) {
            Ok(stamp_record) => (STATUS_OK, encode_stamp(&stamp_record)),
            Err(message) => (STATUS_REJECTED, message.into_bytes()),
        },
        Err(_) => (
            STATUS_REJECTED,
            "stamp is not valid UTF-8".as_bytes().to_vec(),
        ),
    };
    let (pointer, length) = into_buffer(payload);
    *out_ptr = pointer;
    *out_len = length;
    status
}

/// Releases a buffer returned by [`diting_stamp_parse`].
///
/// # Safety
/// `pointer`/`len` must be exactly what the parse call returned, released once.
#[no_mangle]
pub unsafe extern "C" fn diting_stamp_free(pointer: *mut u8, len: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, len, len));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stamp::{Proto, HASH_LEN};
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;
    use base64::Engine;

    struct Payload<'a> {
        bytes: &'a [u8],
        pos: usize,
    }

    impl<'a> Payload<'a> {
        fn new(bytes: &'a [u8]) -> Self {
            Payload { bytes, pos: 0 }
        }
        fn u8(&mut self) -> u8 {
            let value = self.bytes[self.pos];
            self.pos += 1;
            value
        }
        fn u16(&mut self) -> usize {
            let value = u16::from_le_bytes([self.bytes[self.pos], self.bytes[self.pos + 1]]);
            self.pos += 2;
            value as usize
        }
        fn u64(&mut self) -> u64 {
            let mut raw = [0u8; 8];
            raw.copy_from_slice(&self.bytes[self.pos..self.pos + 8]);
            self.pos += 8;
            u64::from_le_bytes(raw)
        }
        fn text(&mut self) -> String {
            let length = self.u16();
            let body = &self.bytes[self.pos..self.pos + length];
            self.pos += length;
            std::str::from_utf8(body).unwrap().to_string()
        }
        fn hash(&mut self) -> [u8; HASH_LEN] {
            let mut hash = [0u8; HASH_LEN];
            hash.copy_from_slice(&self.bytes[self.pos..self.pos + HASH_LEN]);
            self.pos += HASH_LEN;
            hash
        }
        fn at_end(&self) -> bool {
            self.pos == self.bytes.len()
        }
    }

    fn call_parse(text: &str) -> (u32, Vec<u8>) {
        let mut out_ptr: *mut u8 = std::ptr::null_mut();
        let mut out_len: usize = 0;
        let status =
            unsafe { diting_stamp_parse(text.as_ptr(), text.len(), &mut out_ptr, &mut out_len) };
        assert!(!out_ptr.is_null() || out_len == 0);
        let payload = if out_ptr.is_null() {
            Vec::new()
        } else {
            let copy = unsafe { std::slice::from_raw_parts(out_ptr, out_len) }.to_vec();
            unsafe { diting_stamp_free(out_ptr, out_len) };
            copy
        };
        (status, payload)
    }

    fn lp(value: &str) -> Vec<u8> {
        let mut out = vec![value.len() as u8];
        out.extend_from_slice(value.as_bytes());
        out
    }

    fn doh_stamp() -> String {
        let hash = [0x5Au8; HASH_LEN];
        let mut bin = vec![0x02u8];
        bin.extend_from_slice(&3u64.to_le_bytes());
        bin.extend_from_slice(&lp("1.1.1.1"));
        bin.push(HASH_LEN as u8); // one pin, and it is the last element of the VLP
        bin.extend_from_slice(&hash);
        bin.extend_from_slice(&lp("cloudflare-dns.com"));
        bin.extend_from_slice(&lp("/dns-query"));
        bin.push(0x00); // empty bootstrap-IP VLP
        format!("sdns://{}", URL_SAFE_NO_PAD.encode(&bin))
    }

    #[test]
    fn abi_version_is_pinned() {
        assert_eq!(diting_stamp_abi_version(), ABI_VERSION);
    }

    #[test]
    fn parse_payload_matches_the_documented_layout() {
        let (status, payload) = call_parse(&doh_stamp());
        assert_eq!(status, STATUS_OK);

        let mut reader = Payload::new(&payload);
        assert_eq!(reader.u8(), PAYLOAD_LAYOUT_VERSION);
        assert_eq!(reader.u8(), Proto::DoH.code());
        assert_eq!(reader.u64(), 3);
        assert_eq!(reader.text(), "DOH", "protocol enum name");
        assert_eq!(reader.text(), "1.1.1.1:443", "server address");
        assert_eq!(reader.text(), "cloudflare-dns.com", "provider name");
        assert_eq!(reader.text(), "/dns-query", "path");
        assert_eq!(reader.text(), "https://cloudflare-dns.com/dns-query", "url");
        assert_eq!(reader.text(), "cloudflare-dns.com", "server");
        assert_eq!(reader.u16(), 1);
        assert_eq!(reader.hash(), [0x5A; HASH_LEN]);
        assert_eq!(reader.u16(), 0, "no bootstrap IPs in this stamp");
        assert!(reader.at_end(), "payload must be consumed exactly");
    }

    #[test]
    fn rejection_payload_is_the_message() {
        let (status, payload) = call_parse("https://example.com");
        assert_eq!(status, STATUS_REJECTED);
        assert_eq!(
            String::from_utf8(payload).unwrap(),
            "stamps are expected to start with \"sdns:\""
        );
    }

    #[test]
    fn empty_input_is_an_empty_stamp() {
        let (status, payload) = call_parse("");
        assert_eq!(status, STATUS_REJECTED);
        assert_eq!(String::from_utf8(payload).unwrap(), "empty stamp");
    }

    #[test]
    fn null_out_parameters_are_reported() {
        let status = unsafe {
            diting_stamp_parse(b"x".as_ptr(), 1, std::ptr::null_mut(), std::ptr::null_mut())
        };
        assert_eq!(status, STATUS_INVALID_ARGUMENT);
    }

    #[test]
    fn freeing_a_null_pointer_is_a_no_op() {
        unsafe { diting_stamp_free(std::ptr::null_mut(), 0) };
    }
}

//! Name encoding with the RFC 1035 compression map.
//!
//! [`NameWriter`] writes presentation names straight into the message buffer the caller is
//! building. Because the buffer starts at the DNS header, every recorded offset is already
//! message-relative, which is exactly what a compression pointer needs.

use std::collections::HashMap;

/// `maxDomainNameWireOctets` (RFC 1035).
const MAX_NAME_WIRE_OCTETS: usize = 255;
/// Longest label (RFC 1035).
const MAX_LABEL_LEN: usize = 63;
/// Largest offset a 14-bit compression pointer can name.
const MAX_POINTER_OFFSET: usize = 0x3fff;

/// A reusable compression map for one DNS message.
///
/// `write_name` appends the encoded name to the message buffer and registers every suffix it
/// wrote, so a later name sharing that suffix is emitted as a two-byte pointer. The map
/// lowercases suffixes for matching (DNS names are case-insensitive) but writes the labels with
/// the casing the caller supplied.
#[derive(Debug, Clone, Default)]
pub struct NameWriter {
    /// Lowercased, length-prefixed suffix (including the root zero) to absolute message offset.
    offsets: HashMap<Vec<u8>, u16>,
}

impl NameWriter {
    /// A fresh map for a new message.
    pub fn new() -> Self {
        Self::default()
    }

    /// Drops every recorded offset, e.g. when reusing the writer for another message.
    pub fn clear(&mut self) {
        self.offsets.clear();
    }

    /// Encodes `name` at the end of `out` (the whole message, not just the record).
    ///
    /// Returns `false` for a presentation name [`crate::unpack_name`] could not have produced or
    /// one that would exceed 255 wire octets. On failure the buffer and the map are left
    /// untouched, so a builder can abandon the message without cleaning up.
    pub fn write_name(&mut self, out: &mut Vec<u8>, name: &str) -> bool {
        let labels = match parse_labels(name) {
            Some(labels) => labels,
            None => return false,
        };

        let wire_len: usize = labels.iter().map(|label| label.len() + 1).sum::<usize>() + 1;
        if wire_len > MAX_NAME_WIRE_OCTETS {
            return false;
        }

        // keys[i] is the wire suffix labels[i..] followed by the root zero, lowercased.
        let mut keys: Vec<Vec<u8>> = vec![Vec::new(); labels.len() + 1];
        keys[labels.len()].push(0);
        for index in (0..labels.len()).rev() {
            let mut key = Vec::with_capacity(labels[index].len() + 1 + keys[index + 1].len());
            key.push(labels[index].len() as u8);
            key.extend(labels[index].iter().map(|byte| byte.to_ascii_lowercase()));
            key.extend_from_slice(&keys[index + 1]);
            keys[index] = key;
        }

        // Find the longest suffix already present in the message. The root-only suffix is not a
        // useful match (a two-byte pointer instead of a one-byte zero), so stop before it.
        let mut match_at = labels.len();
        let mut match_offset = None;
        for (index, key) in keys[..labels.len()].iter().enumerate() {
            if let Some(&offset) = self.offsets.get(key) {
                match_at = index;
                match_offset = Some(offset);
                break;
            }
        }

        // Remember where we started so a later failure can roll the buffer back.
        let start = out.len();
        for (index, label) in labels[..match_at].iter().enumerate() {
            if out.len() <= MAX_POINTER_OFFSET {
                self.offsets
                    .entry(keys[index].clone())
                    .or_insert(out.len() as u16);
            }
            out.push(label.len() as u8);
            out.extend_from_slice(label);
        }

        match match_offset {
            Some(offset) => {
                out.push(0xc0 | ((offset >> 8) as u8));
                out.push(offset as u8);
            }
            None => out.push(0),
        }

        let written = out.len() - start;
        if written > MAX_NAME_WIRE_OCTETS {
            out.truncate(start);
            // A name with no pointer that is too long cannot have registered a usable suffix;
            // leaving the extra map entries only costs a little memory, never wire correctness.
            return false;
        }
        true
    }
}

/// Encodes one presentation name without compression (a fresh map cannot produce pointers).
pub fn encode_name(out: &mut Vec<u8>, name: &str) -> bool {
    NameWriter::new().write_name(out, name)
}

/// Splits a presentation name the same way [`crate::pack_name`] does: `\DDD` names a byte, `\X`
/// the literal `X`, `.` separates labels and a single trailing `.` is the root.
fn parse_labels(name: &str) -> Option<Vec<Vec<u8>>> {
    if name == "." {
        return Some(Vec::new());
    }
    if name.is_empty() {
        return None;
    }

    let bytes = name.as_bytes();
    let mut labels: Vec<Vec<u8>> = Vec::new();
    let mut label: Vec<u8> = Vec::new();
    let mut index = 0usize;
    let mut closed = false;

    while index < bytes.len() {
        let byte = bytes[index];
        if byte == b'\\' {
            index += 1;
            if index >= bytes.len() {
                return None;
            }
            let escaped = bytes[index];
            if escaped.is_ascii_digit() {
                if index + 2 >= bytes.len() {
                    return None;
                }
                let digits = &bytes[index..index + 3];
                if !digits.iter().all(u8::is_ascii_digit) {
                    return None;
                }
                let value = (digits[0] - b'0') as u32 * 100
                    + (digits[1] - b'0') as u32 * 10
                    + (digits[2] - b'0') as u32;
                if value > 255 {
                    return None;
                }
                label.push(value as u8);
                index += 3;
            } else {
                label.push(escaped);
                index += 1;
            }
            if label.len() > MAX_LABEL_LEN {
                return None;
            }
            continue;
        }

        if byte == b'.' {
            if label.is_empty() {
                return None;
            }
            labels.push(std::mem::take(&mut label));
            closed = true;
            index += 1;
            continue;
        }

        label.push(byte);
        if label.len() > MAX_LABEL_LEN {
            return None;
        }
        index += 1;
    }

    if !label.is_empty() {
        labels.push(label);
    } else if !closed {
        // Only the root name "." has no labels and no trailing dot; empty input was rejected.
        return None;
    }
    Some(labels)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_plain_and_root_names() {
        let mut out = Vec::new();
        assert!(encode_name(&mut out, "example.test."));
        assert_eq!(out, b"\x07example\x04test\x00".to_vec());

        let mut root = Vec::new();
        assert!(encode_name(&mut root, "."));
        assert_eq!(root, vec![0]);
    }

    #[test]
    fn rejects_names_unpack_name_could_not_produce() {
        for name in [
            "",
            ".leading.",
            "double..dot.",
            "trailing\\",
            "a\\300.example.",
        ] {
            let mut out = Vec::new();
            assert!(!encode_name(&mut out, name), "{name:?}");
            assert!(out.is_empty());
        }
    }

    #[test]
    fn compression_reuses_the_longest_suffix() {
        let mut writer = NameWriter::new();
        let mut out = vec![0u8; 12]; // pretend header bytes
        assert!(writer.write_name(&mut out, "www.example.test."));
        let second = out.len();
        assert!(writer.write_name(&mut out, "mail.example.test."));
        // "mail" followed by a pointer to the "example.test." suffix at header+4.
        assert_eq!(&out[second..second + 5], b"\x04mail");
        assert_eq!(out[second + 5], 0xc0);
        assert_eq!(out[second + 6], 0x10);
    }

    #[test]
    fn full_name_match_is_a_single_pointer() {
        let mut writer = NameWriter::new();
        let mut out = Vec::new();
        assert!(writer.write_name(&mut out, "example.test."));
        let second = out.len();
        assert!(writer.write_name(&mut out, "EXAMPLE.TEST."));
        assert_eq!(&out[second..], &[0xc0, 0x00]);
    }
}

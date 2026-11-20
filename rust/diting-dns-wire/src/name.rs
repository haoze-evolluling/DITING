pub const MAX_NAME_WIRE_OCTETS: i32 = 255;
const MAX_COMPRESSION_POINTERS: usize = 126;

pub fn unpack_name(wire: &[u8], start: usize, limit: usize) -> Option<(String, usize)> {
    let limit = limit.min(wire.len());
    let mut text = String::new();
    let mut offset = start;
    let mut budget = MAX_NAME_WIRE_OCTETS;
    let mut pointers = 0usize;
    let mut consumed: Option<usize> = None;

    loop {
        if offset >= limit {
            return None;
        }
        let byte = wire[offset] as usize;
        offset += 1;
        match byte & 0xc0 {
            0x00 => {
                if byte == 0 {
                    if consumed.is_none() {
                        consumed = Some(offset);
                    }
                    break;
                }
                if offset + byte > limit {
                    return None;
                }
                budget -= (byte + 1) as i32;
                if budget <= 0 {
                    return None;
                }
                for &label in &wire[offset..offset + byte] {
                    push_escaped(&mut text, label);
                }
                text.push('.');
                offset += byte;
            }
            0xc0 => {
                if offset >= limit {
                    return None;
                }
                let low = wire[offset] as usize;
                offset += 1;
                if consumed.is_none() {
                    consumed = Some(offset);
                }
                pointers += 1;
                if pointers > MAX_COMPRESSION_POINTERS {
                    return None;
                }
                offset = ((byte & 0x3f) << 8) | low;
            }
            _ => return None,
        }
    }

    if text.is_empty() {
        text.push('.');
    }
    Some((text, consumed?))
}

fn push_escaped(text: &mut String, byte: u8) {
    if matches!(
        byte,
        b'.' | b' ' | b'\'' | b'@' | b';' | b'(' | b')' | b'"' | b'\\'
    ) {
        text.push('\\');
        text.push(byte as char);
    } else if !(b' '..=b'~').contains(&byte) {
        text.push('\\');
        text.push((b'0' + byte / 100) as char);
        text.push((b'0' + (byte / 10) % 10) as char);
        text.push((b'0' + byte % 10) as char);
    } else {
        text.push(byte as char);
    }
}

pub fn pack_name(name: &str, out: &mut Vec<u8>) -> bool {
    let start = out.len();
    if name == "." {
        out.push(0);
        return true;
    }

    let bytes = name.as_bytes();
    let mut label: Vec<u8> = Vec::with_capacity(64);
    let mut index = 0usize;
    let mut closed = false;

    let flush = |label: &mut Vec<u8>, out: &mut Vec<u8>, closed: &mut bool| -> bool {
        if label.is_empty() || label.len() > 63 {
            return false;
        }
        out.push(label.len() as u8);
        out.extend_from_slice(label);
        label.clear();
        *closed = true;
        true
    };

    while index < bytes.len() {
        let byte = bytes[index];
        if byte == b'\\' {
            index += 1;
            if index >= bytes.len() {
                out.truncate(start);
                return false;
            }
            let escaped = bytes[index];
            if escaped.is_ascii_digit() {
                if index + 2 >= bytes.len() {
                    out.truncate(start);
                    return false;
                }
                let digits = &bytes[index..index + 3];
                if !digits.iter().all(|digit| digit.is_ascii_digit()) {
                    out.truncate(start);
                    return false;
                }
                let value = (digits[0] - b'0') as u32 * 100
                    + (digits[1] - b'0') as u32 * 10
                    + (digits[2] - b'0') as u32;
                if value > 255 {
                    out.truncate(start);
                    return false;
                }
                label.push(value as u8);
                index += 3;
            } else {
                label.push(escaped);
                index += 1;
            }
            continue;
        }

        if byte == b'.' {
            if !flush(&mut label, out, &mut closed) {
                out.truncate(start);
                return false;
            }
            index += 1;
            continue;
        }

        label.push(byte);
        index += 1;
    }

    if !label.is_empty() {
        if !flush(&mut label, out, &mut closed) {
            out.truncate(start);
            return false;
        }
    } else if !closed {
        out.truncate(start);
        return false;
    }

    out.push(0);
    if out.len() - start > MAX_NAME_WIRE_OCTETS as usize {
        out.truncate(start);
        return false;
    }
    true
}

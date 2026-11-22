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

/// 校验并跳过一个压缩或非压缩 DNS 域名，返回它在 `wire` 中的结束偏移，不构造 `String`。
pub fn skip_name(wire: &[u8], start: usize, limit: usize) -> Option<usize> {
    let limit = limit.min(wire.len());
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

    consumed
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skip_name_matches_unpack_name_on_valid_and_invalid_inputs() {
        let mut wire = Vec::new();
        assert!(pack_name("www.example.com.", &mut wire));
        let second_start = wire.len();
        // 压缩指针：sub + 指向偏移 4 ("example.com.")
        wire.extend_from_slice(&[3, b's', b'u', b'b', 0xc0, 0x04]);
        let root_start = wire.len();
        wire.push(0);

        for start in [0, second_start, root_start] {
            let expected = unpack_name(&wire, start, wire.len()).map(|(_, end)| end);
            assert_eq!(skip_name(&wire, start, wire.len()), expected);
        }

        // 自指压缩循环必须返回 None
        let loop_wire = [0xc0, 0x00];
        assert_eq!(unpack_name(&loop_wire, 0, loop_wire.len()), None);
        assert_eq!(skip_name(&loop_wire, 0, loop_wire.len()), None);

        // 截断标签必须返回 None
        let truncated = [5, b'a', b'b'];
        assert_eq!(unpack_name(&truncated, 0, truncated.len()), None);
        assert_eq!(skip_name(&truncated, 0, truncated.len()), None);
    }
}

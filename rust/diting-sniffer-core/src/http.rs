pub fn looks_like_http_request(bytes: &[u8]) -> bool {
    if bytes.len() < 7 {
        return false;
    }
    for index in 0..bytes.len().min(16) {
        if bytes[index] == b' ' {
            return index + 2 < bytes.len() && bytes[index + 1] == b'/';
        }
        if !bytes[index].is_ascii_alphabetic() {
            return false;
        }
    }
    false
}

pub fn parse_http_host(bytes: &[u8]) -> &[u8] {
    let mut index = 0;
    while index < bytes.len() {
        let mut newline = None;
        for cursor in index..bytes.len().saturating_sub(1) {
            if bytes[cursor] == b'\r' && bytes[cursor + 1] == b'\n' {
                newline = Some(cursor);
                break;
            }
        }
        let Some(newline) = newline else {
            return &[];
        };
        let line = &bytes[index..newline];
        index = newline + 2;

        if line.is_empty() {
            return &[];
        }

        let Some(colon) = line.iter().position(|byte| *byte == b':') else {
            continue;
        };
        if colon == 0 {
            continue;
        }
        if !equal_fold_host(&line[..colon]) {
            continue;
        }
        let value = go_trim_space_bytes(&line[colon + 1..]);
        return match value.iter().position(|byte| *byte == b':') {
            Some(port) => &value[..port],
            None => value,
        };
    }
    &[]
}

fn equal_fold_host(name: &[u8]) -> bool {
    const TARGET: [char; 4] = ['h', 'o', 's', 't'];
    let mut position = 0;
    let mut index = 0;
    while position < name.len() {
        let (rune, size) = decode_rune(&name[position..]);
        let Some(expected) = TARGET.get(index) else {
            return false;
        };
        let folded = match rune {
            'A'..='Z' => rune.to_ascii_lowercase(),
            '\u{017F}' => 's',
            other => other,
        };
        if folded != *expected {
            return false;
        }
        position += size;
        index += 1;
    }
    index == TARGET.len()
}

pub fn go_trim_space_bytes(bytes: &[u8]) -> &[u8] {
    let mut start = 0;
    while start < bytes.len() {
        let (rune, size) = decode_rune(&bytes[start..]);
        if !rune.is_whitespace() {
            break;
        }
        start += size;
    }
    let mut end = bytes.len();
    while end > start {
        let (rune, size) = decode_last_rune(&bytes[start..end]);
        if !rune.is_whitespace() {
            break;
        }
        end -= size;
    }
    &bytes[start..end]
}

fn decode_rune(bytes: &[u8]) -> (char, usize) {
    let take = bytes.len().min(4);
    match std::str::from_utf8(&bytes[..take]) {
        Ok(text) => {
            let rune = text.chars().next().expect("non-empty slice");
            (rune, rune.len_utf8())
        }
        Err(error) if error.valid_up_to() > 0 => {
            let valid = &bytes[..error.valid_up_to()];
            let rune = std::str::from_utf8(valid)
                .expect("valid prefix")
                .chars()
                .next()
                .expect("non-empty prefix");
            (rune, rune.len_utf8())
        }
        Err(_) => ('\u{FFFD}', 1),
    }
}

fn decode_last_rune(bytes: &[u8]) -> (char, usize) {
    let start = bytes.len().saturating_sub(4);
    for index in start..bytes.len() {
        let (rune, size) = decode_rune(&bytes[index..]);
        if size == bytes.len() - index {
            return (rune, size);
        }
    }
    ('\u{FFFD}', 1)
}

#[cfg(test)]
mod tests;

//! `looksLikeHTTPRequest` and `parseHTTPHost`: plaintext HTTP sniffing.
//!
//! Only HTTP/1.x is recognized, and only enough of it to find the authority the client is asking
//! for: a method made of letters followed by a space and a `/`, then a header block whose `Host`
//! name compares case-insensitively. Nothing is parsed into strings — header bytes can be
//! anything, and the Go caller lowercases the value afterwards.
//!
//! Two details are ports, not choices:
//!
//! * [`go_trim_space_bytes`] is `strings.TrimSpace` over bytes. Go trims runes and keeps the
//!   original bytes, so an invalid UTF-8 byte is not whitespace and stops the trim (a `String`
//!   round-trip would have replaced it with U+FFFD).
//! * the header name comparison is `strings.EqualFold(name, "Host")`. For ASCII targets Unicode
//!   simple folding adds exactly one non-ASCII rune, `ſ` (U+017F), which folds to `s`.

/// `looksLikeHTTPRequest`: a letter-only method, a space, and a request target starting with `/`.
///
/// The Go loop only inspects the first 16 bytes, so a method longer than that is not an HTTP
/// request even if a space follows.
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

/// `parseHTTPHost`: the first `Host` header value, trimmed and with any port cut off.
///
/// Returns `&[]` when the headers are not terminated by `\r\n\r\n`, when no `Host` line exists, or
/// when the value is empty. A line that starts with `:` is not a header and is skipped.
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

/// `strings.EqualFold(name, "Host")`.
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
            // The only non-ASCII rune whose simple fold is an ASCII letter of "Host".
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

/// `strings.TrimSpace` over raw bytes: trims runes, keeps the bytes it does not trim.
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

/// `utf8.DecodeRune`: the first rune, or `(U+FFFD, 1)` for invalid or truncated bytes.
fn decode_rune(bytes: &[u8]) -> (char, usize) {
    let take = bytes.len().min(4);
    match std::str::from_utf8(&bytes[..take]) {
        Ok(text) => {
            let rune = text.chars().next().expect("non-empty slice");
            (rune, rune.len_utf8())
        }
        Err(error) if error.valid_up_to() > 0 => {
            let valid = &bytes[..error.valid_up_to()];
            // `valid_up_to` guarantees the prefix is valid UTF-8.
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

/// `utf8.DecodeLastRune`: the last rune, or `(U+FFFD, 1)` when the tail is not a valid encoding.
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

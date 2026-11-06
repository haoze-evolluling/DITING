//! Go's `path.Match` and the `matchHostPattern` built on top of it.
//!
//! The bypass rules that were matched with `path.Match(pattern, host)` decide which hosts are
//! excluded from TLS interception, so the port keeps every branch of `path/match.go` — including
//! the chunk scanner, the `/` rules, character classes with escapes, and `ErrBadPattern`. A
//! pattern Go rejected must be rejected here too, and for the same reason: a rule that suddenly
//! compiles would start bypassing interception.
//!
//! The pattern is matched against bytes exactly like the Go original (`chunk[0] != s[0]` is a byte
//! comparison); only `?` and character classes decode a rune, again like Go.

use diting_go_compat::text::{go_lower, go_trim_space};

/// `path.ErrBadPattern`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BadPattern;

/// Go's `utf8.RuneError`; also the value `utf8.DecodeRuneInString` reports for invalid input.
const RUNE_ERROR: u32 = 0xFFFD;

/// `path.Match`: `*` never crosses a `/`, everything else is live.
pub fn path_match(pattern: &str, name: &str) -> Result<bool, BadPattern> {
    let mut pattern = pattern.as_bytes();
    let mut name = name.as_bytes();

    'outer: while !pattern.is_empty() {
        let (star, chunk, rest) = scan_chunk(pattern);
        pattern = rest;

        if star && chunk.is_empty() {
            // Trailing * matches the rest of the string unless it holds a `/`.
            return Ok(!name.contains(&b'/'));
        }

        let (rest_name, ok, bad) = match_chunk(chunk, name);
        if ok && (rest_name.is_empty() || !pattern.is_empty()) {
            name = rest_name;
            continue;
        }
        if bad {
            return Err(BadPattern);
        }

        if star {
            // Look for a match skipping one byte at a time; never skip a `/`.
            let mut index = 0;
            while index < name.len() && name[index] != b'/' {
                let (rest_name, ok, bad) = match_chunk(chunk, &name[index + 1..]);
                if ok {
                    // The last chunk must consume the whole name, otherwise keep searching.
                    if pattern.is_empty() && !rest_name.is_empty() {
                        index += 1;
                        continue;
                    }
                    name = rest_name;
                    continue 'outer;
                }
                if bad {
                    return Err(BadPattern);
                }
                index += 1;
            }
        }

        // Before reporting "no match", check that the rest of the pattern is well formed.
        let mut rest = pattern;
        while !rest.is_empty() {
            let (_star, chunk, next) = scan_chunk(rest);
            rest = next;
            if match_chunk(chunk, &[]).2 {
                return Err(BadPattern);
            }
        }
        return Ok(false);
    }

    Ok(name.is_empty())
}

/// `path.scanChunk`: leading stars, then the next chunk (a `*` outside a class ends it).
fn scan_chunk(pattern: &[u8]) -> (bool, &[u8], &[u8]) {
    let mut start = 0;
    let mut star = false;
    while start < pattern.len() && pattern[start] == b'*' {
        start += 1;
        star = true;
    }

    let mut in_range = false;
    let mut index = start;
    while index < pattern.len() {
        match pattern[index] {
            b'\\' => {
                // A bad escape is reported by match_chunk, not here.
                if index + 1 < pattern.len() {
                    index += 1;
                }
            }
            b'[' => in_range = true,
            b']' => in_range = false,
            b'*' if !in_range => break,
            _ => {}
        }
        index += 1;
    }

    (star, &pattern[start..index], &pattern[index..])
}

/// `path.matchChunk`: matches one chunk at the start of `s`, returning the unmatched rest.
///
/// The third element is Go's `err`: the pattern is malformed. `ok` can be false while `bad` is
/// set, and the caller checks `ok` first exactly like Go does.
fn match_chunk<'a>(mut chunk: &'a [u8], mut s: &'a [u8]) -> (&'a [u8], bool, bool) {
    // Once the match has failed the loop keeps validating the pattern but stops reading `s`.
    let mut failed = false;

    while !chunk.is_empty() {
        if !failed && s.is_empty() {
            failed = true;
        }
        match chunk[0] {
            b'[' => {
                let mut rune = 0;
                if !failed {
                    let (decoded, width) = decode_rune(s);
                    rune = decoded;
                    s = &s[width..];
                }
                chunk = &chunk[1..];

                let mut negated = false;
                if !chunk.is_empty() && chunk[0] == b'^' {
                    negated = true;
                    chunk = &chunk[1..];
                }

                let mut matched = false;
                let mut ranges = 0;
                loop {
                    if !chunk.is_empty() && chunk[0] == b']' && ranges > 0 {
                        chunk = &chunk[1..];
                        break;
                    }
                    let (low, rest, bad) = get_esc(chunk);
                    if bad {
                        return (&[], false, true);
                    }
                    chunk = rest;
                    let mut high = low;
                    // get_esc guarantees a non-empty rest, so this index is safe.
                    if chunk[0] == b'-' {
                        let (decoded, rest, bad) = get_esc(&chunk[1..]);
                        if bad {
                            return (&[], false, true);
                        }
                        high = decoded;
                        chunk = rest;
                    }
                    if low <= rune && rune <= high {
                        matched = true;
                    }
                    ranges += 1;
                }
                if matched == negated {
                    failed = true;
                }
            }
            b'?' => {
                if !failed {
                    // `failed` is only cleared above, so `s` is non-empty here.
                    if s[0] == b'/' {
                        failed = true;
                    }
                    let (_rune, width) = decode_rune(s);
                    s = &s[width..];
                }
                chunk = &chunk[1..];
            }
            b'\\' => {
                chunk = &chunk[1..];
                if chunk.is_empty() {
                    return (&[], false, true);
                }
                // Go falls through to the literal case with the escape consumed.
                if !failed {
                    if chunk[0] != s[0] {
                        failed = true;
                    }
                    s = &s[1..];
                }
                chunk = &chunk[1..];
            }
            _ => {
                if !failed {
                    if chunk[0] != s[0] {
                        failed = true;
                    }
                    s = &s[1..];
                }
                chunk = &chunk[1..];
            }
        }
    }

    if failed {
        (&[], false, false)
    } else {
        (s, true, false)
    }
}

/// `path.getEsc`: one class member, optionally escaped, followed by at least one more byte.
fn get_esc(chunk: &[u8]) -> (u32, &[u8], bool) {
    if chunk.is_empty() || chunk[0] == b'-' || chunk[0] == b']' {
        return (0, chunk, true);
    }
    let mut chunk = chunk;
    if chunk[0] == b'\\' {
        chunk = &chunk[1..];
        if chunk.is_empty() {
            return (0, chunk, true);
        }
    }
    let (rune, width) = decode_rune(chunk);
    let bad = (rune == RUNE_ERROR && width == 1) || chunk.len() == width;
    (rune, &chunk[width..], bad)
}

/// `utf8.DecodeRuneInString`: the decoded rune and how many bytes it took (invalid input is
/// `RuneError` in one byte).
fn decode_rune(s: &[u8]) -> (u32, usize) {
    let first = s[0];
    if first < 0x80 {
        return (u32::from(first), 1);
    }
    let width = match first {
        0xC2..=0xDF => 2,
        0xE0..=0xEF => 3,
        0xF0..=0xF4 => 4,
        _ => return (RUNE_ERROR, 1),
    };
    if s.len() < width {
        return (RUNE_ERROR, 1);
    }
    match std::str::from_utf8(&s[..width]) {
        Ok(text) => match text.chars().next() {
            Some(rune) => (rune as u32, width),
            None => (RUNE_ERROR, 1),
        },
        Err(_) => (RUNE_ERROR, 1),
    }
}

/// `matchHostPattern`: lowers and trims both sides, strips the AdGuard decorations (`@@`, `||`,
/// trailing `^`), then treats a pattern without `*` as a host suffix.
pub fn match_host_pattern(pattern: &str, host: &str) -> bool {
    let pattern = go_lower(go_trim_space(pattern));
    let host = go_lower(go_trim_space(host));
    if pattern.is_empty() || host.is_empty() {
        return false;
    }

    let host = host.as_ref();
    let pattern = pattern.as_ref();
    let pattern = pattern.strip_prefix("@@").unwrap_or(pattern);
    let pattern = pattern.strip_prefix("||").unwrap_or(pattern);
    let pattern = pattern.trim_end_matches('^');

    if !pattern.contains('*') {
        let clean = pattern.strip_prefix('.').unwrap_or(pattern);
        return host == clean || host.ends_with(&format!(".{clean}"));
    }

    if let Some(suffix) = pattern.strip_prefix("*.") {
        if host == suffix {
            return true;
        }
    }
    path_match(pattern, host).unwrap_or(false)
}

#[cfg(test)]
mod tests;

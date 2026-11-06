//! Test-only decoding for the migration fixtures under `tests/fixtures`.
//!
//! The generator wrote TSV with `\\` for a literal backslash, `\t` for a tab and `\n` for a
//! newline; only the first row of the corpora (empty pattern, empty name) and the lone-backslash
//! pattern actually need the escapes.

/// Undoes the generator's escaping.
pub(crate) fn unescape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('\\') => out.push('\\'),
            Some('t') => out.push('\t'),
            Some('n') => out.push('\n'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

#[test]
fn unescape_handles_the_escapes_it_writes() {
    assert_eq!(unescape("a\\\\*b"), "a\\*b");
    assert_eq!(unescape("a\\tb"), "a\tb");
    assert_eq!(unescape("a\\nb"), "a\nb");
    assert_eq!(unescape("plain"), "plain");
    assert_eq!(unescape("trailing\\"), "trailing\\");
}

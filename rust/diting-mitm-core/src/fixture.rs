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

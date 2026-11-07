//! `%q` shapes: the error texts reach the settings screen verbatim.

use super::*;

#[test]
fn quotes_like_fmt_q() {
    assert_eq!(go_quote(""), "\"\"");
    assert_eq!(go_quote("PLAIN"), "\"PLAIN\"");
    assert_eq!(go_quote("a b"), "\"a b\"");
    assert_eq!(go_quote("say \"hi\""), "\"say \\\"hi\\\"\"");
    assert_eq!(go_quote("back\\slash"), "\"back\\\\slash\"");
    assert_eq!(go_quote("line\nbreak"), "\"line\\nbreak\"");
    assert_eq!(go_quote("tab\there"), "\"tab\\there\"");
    assert_eq!(go_quote("\u{1}"), "\"\\x01\"");
    assert_eq!(go_quote("\r"), "\"\\r\"");
}

#[test]
fn printable_non_ascii_is_not_escaped() {
    assert_eq!(go_quote("例子.example"), "\"例子.example\"");
    assert_eq!(go_quote("İstanbul"), "\"İstanbul\"");
    // A combining accent is printable too, so it stays as text.
    assert_eq!(go_quote("e\u{301}"), "\"e\u{301}\"");
}

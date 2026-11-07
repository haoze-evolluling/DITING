//! Go's `%q` for strings, used by every error text this kernel returns.
//!
//! The messages reach the settings screen verbatim (`unsupported DNS mode "nope"`,
//! `invalid DOH URL "dns.google"`), so the quoting has to be Go's: double quotes, the short escapes
//! for `\a \b \f \n \r \t \v \\`, `\xNN` for other control bytes, and printable non-ASCII kept as
//! itself. Go emits `\uNNNN` for a control rune it cannot spell otherwise, which is what the last arm
//! does (a control rune outside the short list and above 0x7f).

use std::fmt::Write as _;

/// `fmt.Sprintf("%q", text)` for a string.
pub fn go_quote(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{7}' => out.push_str("\\a"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{b}' => out.push_str("\\v"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                let _ = write!(out, "\\x{:02x}", c as u32);
            }
            // Printable non-ASCII stays printable: `%q` keeps UTF-8 text as text.
            c if !c.is_control() => out.push(c),
            c => {
                for unit in c.to_string().encode_utf16() {
                    let _ = write!(out, "\\u{unit:04x}");
                }
            }
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests;

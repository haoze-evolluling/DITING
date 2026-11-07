//! The page hostname on the injected `<link>`, spelled the way the Go helper spelled it.
//!
//! The stylesheet URL carries the page host (`/cosmetic.css?h=<host>`) so the local asset server can
//! serve only the rules scoped to that host plus its `#@#` exceptions. The value has to match the
//! stored rule domains, which is why `normalizeCosmeticHost` lowercases, drops the port (but only
//! when `net.SplitHostPort` accepted the authority) and strips one trailing dot.
//!
//! [`query_escape`] is `url.QueryEscape`: bytes, not runes, with `+` for the space and upper-case hex
//! for everything outside the unreserved set.

use diting_go_compat::text::{go_lower, go_trim_space};

/// The URL path the injected `<link>` points at.
pub const ASSET_PATH: &str = "/cosmetic.css";

/// `normalizeCosmeticHost`: lowercase, trim, drop the port, strip one trailing dot.
///
/// The bracketed branch returns early without the trailing-dot trim, exactly like the Go version: a
/// bracketed authority is returned as written up to its last `]`, port included if it sits after it.
pub fn normalize_host(host: &str) -> String {
    let lowered = go_lower(go_trim_space(host)).into_owned();
    if lowered.starts_with('[') {
        return match lowered.rfind(']') {
            Some(index) => lowered[..=index].to_string(),
            None => lowered,
        };
    }
    let trimmed = match lowered.rfind(':') {
        Some(index) if split_host_port_ok(&lowered) => lowered[..index].to_string(),
        _ => lowered,
    };
    match trimmed.strip_suffix('.') {
        Some(without_dot) => without_dot.to_string(),
        None => trimmed,
    }
}

/// Whether `net.SplitHostPort` accepts `authority`, which is the only thing that lets the port go.
///
/// Only the shape matters (`SplitHostPort` does not validate the port value): a bracketed host needs
/// its `]` right before the last `:`, an unbracketed one may have neither another `:` nor any `]`
/// before it. A `]` in the port is fine — nothing validates it.
pub fn split_host_port_ok(authority: &str) -> bool {
    let bytes = authority.as_bytes();
    let Some(colon) = bytes.iter().rposition(|byte| *byte == b':') else {
        return false;
    };
    if bytes[0] == b'[' {
        return match bytes.iter().position(|byte| *byte == b']') {
            Some(close) => close + 1 == colon,
            None => false,
        };
    }
    !bytes[..colon].contains(&b':') && !bytes[..colon].contains(&b']')
}

/// `url.QueryEscape`: unreserved bytes stay, the space becomes `+`, everything else is `%XX`.
pub fn query_escape(value: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut escaped = String::with_capacity(value.len());
    for byte in value.as_bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            escaped.push(*byte as char);
        } else if *byte == b' ' {
            escaped.push('+');
        } else {
            escaped.push('%');
            escaped.push(HEX[usize::from(byte >> 4)] as char);
            escaped.push(HEX[usize::from(byte & 0x0f)] as char);
        }
    }
    escaped
}

/// `cosmeticLinkTag`: the `<link>` tag for one page hostname under `asset_host`.
pub fn link_tag(host: &str, asset_host: &str) -> String {
    let normalized = normalize_host(host);
    let mut href = format!("https://{asset_host}{ASSET_PATH}");
    if !normalized.is_empty() {
        href.push_str("?h=");
        href.push_str(&query_escape(&normalized));
    }
    format!(r#"<link rel="stylesheet" href="{href}">"#)
}

#[cfg(test)]
mod tests;

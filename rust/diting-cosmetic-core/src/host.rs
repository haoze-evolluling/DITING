use diting_go_compat::text::{go_lower, go_trim_space};

pub const ASSET_PATH: &str = "/cosmetic.css";

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

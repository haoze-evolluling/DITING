use std::borrow::Cow;

use diting_go_compat::text::{go_lower, go_trim_space};
use sha2::{Digest, Sha256};

pub const HASH_PREFIX_LEN: usize = 2;
pub const HASH_SIZE: usize = 32;
pub const HASH_HEX_SIZE: usize = HASH_SIZE * 2;
pub const HASH_SUB_DOMAIN_NUM: usize = 4;

pub type HostnameHash = [u8; HASH_SIZE];
pub type HashPrefix = [u8; HASH_PREFIX_LEN];

pub fn normalize_check_host(host: &str) -> Option<String> {
    let lowered = go_lower(go_trim_space(host));
    let trimmed = lowered.trim_matches('.');
    if trimmed.is_empty() {
        return None;
    }
    if !is_domain_name(&fqdn(trimmed)) {
        return None;
    }
    Some(trimmed.to_string())
}

pub fn hostname_to_hashes(host: &str) -> Vec<HostnameHash> {
    let public_suffix = icann_public_suffix(host).unwrap_or("");
    let truncated = truncate_to_labels(host, HASH_SUB_DOMAIN_NUM);

    let mut hashes = Vec::with_capacity(HASH_SUB_DOMAIN_NUM);
    for suffix in domain_suffixes(truncated) {
        if suffix == public_suffix {
            break;
        }
        hashes.push(digest(suffix));
    }
    hashes
}

pub fn build_question_name(hashes: &[HostnameHash], suffix: &str) -> String {
    let mut name = String::with_capacity(hashes.len() * (HASH_PREFIX_LEN * 2 + 1) + suffix.len());
    for hash in hashes {
        name.push_str(&hex_encode(&hash[..HASH_PREFIX_LEN]));
        name.push('.');
    }
    name.push_str(suffix);
    name
}

pub fn parse_txt_hashes<S: AsRef<str>>(texts: &[S]) -> Vec<HostnameHash> {
    let mut out = Vec::new();
    for text in texts {
        let bytes = text.as_ref().as_bytes();
        if bytes.len() != HASH_HEX_SIZE {
            continue;
        }
        let Some(hash) = hex_decode_32(bytes) else {
            continue;
        };
        out.push(hash);
    }
    out
}

pub fn hash_prefix(hash: &HostnameHash) -> HashPrefix {
    let mut prefix = [0u8; HASH_PREFIX_LEN];
    prefix.copy_from_slice(&hash[..HASH_PREFIX_LEN]);
    prefix
}

fn digest(label: &str) -> HostnameHash {
    let mut hasher = Sha256::new();
    hasher.update(label.as_bytes());
    hasher.finalize().into()
}

fn icann_public_suffix(host: &str) -> Option<&str> {
    let suffix = psl::suffix(host.as_bytes())?;
    if suffix.typ() != Some(psl::Type::Icann) {
        return None;
    }
    std::str::from_utf8(suffix.as_bytes()).ok()
}

fn truncate_to_labels(host: &str, labels: usize) -> &str {
    let mut dots = 0usize;
    for (index, ch) in host.char_indices().rev() {
        if ch == '.' {
            dots += 1;
            if dots == labels {
                return &host[index + 1..];
            }
        }
    }
    host
}

fn domain_suffixes(host: &str) -> Vec<&str> {
    let mut out = Vec::with_capacity(host.bytes().filter(|byte| *byte == b'.').count() + 1);
    let mut start = 0usize;
    loop {
        out.push(&host[start..]);
        match host[start..].find('.') {
            Some(offset) => start += offset + 1,
            None => break,
        }
    }
    out
}

fn hex_encode(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(DIGITS[(byte >> 4) as usize] as char);
        out.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    out
}

fn hex_decode_32(bytes: &[u8]) -> Option<HostnameHash> {
    let mut out = [0u8; HASH_SIZE];
    let (pairs, remainder) = bytes.as_chunks::<2>();
    if !remainder.is_empty() {
        return None;
    }
    for (index, pair) in pairs.iter().enumerate() {
        let high = hex_value(pair[0])?;
        let low = hex_value(pair[1])?;
        out[index] = (high << 4) | low;
    }
    Some(out)
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn is_domain_name(host: &str) -> bool {
    if host.is_empty() {
        return false;
    }
    let s = fqdn(host);
    let bytes = s.as_bytes();
    const LENMSG: usize = 256;

    let mut off = 0usize;
    let mut begin = 0usize;
    let mut was_dot = false;
    let mut escape = false;
    let mut index = 0usize;
    while index < bytes.len() {
        match bytes[index] {
            b'\\' => {
                escape = !escape;
                if off + 1 > LENMSG {
                    return false;
                }
                if is_ddd(&bytes[index + 1..]) {
                    index += 3;
                    begin += 3;
                } else {
                    index += 1;
                    begin += 1;
                }
                was_dot = false;
            }
            b'.' => {
                escape = false;
                if index == 0 && bytes.len() > 1 {
                    return false;
                }
                if was_dot {
                    return false;
                }
                was_dot = true;
                let label_len = index.saturating_sub(begin);
                if label_len >= 1 << 6 {
                    return false;
                }
                off += 1 + label_len;
                if off > LENMSG {
                    return false;
                }
                begin = index + 1;
            }
            _ => {
                escape = false;
                was_dot = false;
            }
        }
        index += 1;
    }
    !escape
}

fn fqdn(host: &str) -> Cow<'_, str> {
    if is_fqdn(host) {
        Cow::Borrowed(host)
    } else {
        Cow::Owned(format!("{host}."))
    }
}

fn is_fqdn(host: &str) -> bool {
    let Some(stripped) = host.strip_suffix('.') else {
        return false;
    };
    if stripped.is_empty() || !stripped.ends_with('\\') {
        return true;
    }
    let last_other = stripped
        .char_indices()
        .rev()
        .find(|(_, ch)| *ch != '\\')
        .map(|(index, _)| index as isize)
        .unwrap_or(-1);
    (stripped.len() as isize - last_other) % 2 != 0
}

fn is_ddd(bytes: &[u8]) -> bool {
    bytes.len() >= 3 && bytes[..3].iter().all(u8::is_ascii_digit)
}

#[cfg(test)]
mod tests;

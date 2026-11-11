//! Host canonicalization, digest set, query name and TXT answer parsing.
//!
//! Everything here was `safebrowsing.go` before the migration: `normalizeCheckHost` (with the
//! `dns.IsDomainName` check it delegates to), `hostnameToHashes`, `domainSuffixes`,
//! `buildHashQuestion`'s name and `collectHashes`.
//!
//! Two deliberate copies of Go standard-library behaviour live here:
//!
//! * `normalize_check_host` uses [`diting_go_compat::text::go_lower`] / `go_trim_space`, not
//!   `str::to_lowercase`, because `strings.ToLower` maps one rune to one rune (`U+0130` becomes a
//!   plain `i`).
//! * `is_domain_name` is a byte-for-byte port of miekg/dns `IsDomainName`, including its escaped
//!   label arithmetic and the 255-byte ceiling. Hosts reaching this kernel come from DNS question
//!   names, so the escaped forms are effectively unreachable — but a port that "simplifies" them
//!   would accept a name the old implementation rejected.

use std::borrow::Cow;

use diting_go_compat::text::{go_lower, go_trim_space};
use sha2::{Digest, Sha256};

/// Bytes of a digest that travel on the wire (and key the cache).
pub const HASH_PREFIX_LEN: usize = 2;
/// SHA-256 digest length.
pub const HASH_SIZE: usize = 32;
/// Hex length of a digest; also the only legal TXT chunk length.
pub const HASH_HEX_SIZE: usize = HASH_SIZE * 2;
/// How many trailing labels (eTLD+1 included) are hashed.
pub const HASH_SUB_DOMAIN_NUM: usize = 4;

/// One domain's SHA-256 digest.
pub type HostnameHash = [u8; HASH_SIZE];
/// The first [`HASH_PREFIX_LEN`] bytes of a digest; the cache key.
pub type HashPrefix = [u8; HASH_PREFIX_LEN];

/// `normalizeCheckHost`: lowercase, trim, drop surrounding dots, then insist on a valid name.
///
/// Returns `None` for the empty/degenerate inputs (`""`, `"  "`, `"."`, `"a..b"`), which is the
/// "no verdict" signal the caller turns into a pass.
pub fn normalize_check_host(host: &str) -> Option<String> {
    let lowered = go_lower(go_trim_space(host));
    let trimmed = lowered.trim_matches('.');
    if trimmed.is_empty() {
        return None;
    }
    // The old call was `dns.IsDomainName(dns.Fqdn(host))`, and `IsDomainName` itself calls `Fqdn`
    // again — so a name whose final dot looks escaped gets two dots. Reproduced rather than
    // "fixed": the only hosts that notice are hand-built ones ending in a backslash.
    if !is_domain_name(&fqdn(trimmed)) {
        return None;
    }
    Some(trimmed.to_string())
}

/// The digest set for a normalized host: the host itself and each parent, down to eTLD+1.
///
/// The public suffix itself is skipped (`com` is never "the blocked site"), and a host deeper
/// than [`HASH_SUB_DOMAIN_NUM`] labels is first truncated so the query name stays inside the DNS
/// label budget. Non-ICANN suffixes (`dyndns.org` and friends) have no registrable domain to
/// anchor on, so the old implementation walked every label; that is preserved.
///
/// The host must already be normalized (lowercase, no surrounding dots) — same contract as the Go
/// caller had.
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

/// The `u8`-length query name of a hash-prefix exchange: `abcd.ef01.sb.dns.adguard.com.`.
///
/// An empty digest set still produces the bare suffix (the old `buildHashQuestion` did too); the
/// caller never sends it because an empty digest set is reported as "nothing to check".
pub fn build_question_name(hashes: &[HostnameHash], suffix: &str) -> String {
    let mut name = String::with_capacity(hashes.len() * (HASH_PREFIX_LEN * 2 + 1) + suffix.len());
    for hash in hashes {
        name.push_str(&hex_encode(&hash[..HASH_PREFIX_LEN]));
        name.push('.');
    }
    name.push_str(suffix);
    name
}

/// `collectHashes`: keep only TXT chunks that decode to exactly one digest.
///
/// A chunk of the wrong length or with a non-hex byte is dropped rather than turned into a digest
/// that could never match — the answer belongs to the third party, and a format change must not
/// become a spurious block.
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

/// `hashPrefixOf`.
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

/// The ICANN public suffix of `host`, or `None` when no ICANN rule matched.
///
/// The Go side asked `publicsuffix.PublicSuffix` and dropped the answer unless `icann` was true;
/// private suffixes (`github.io`) and unknown TLDs therefore behave the same: no anchor, every
/// label is hashed. The PSL snapshot comes from the `psl` crate instead of `golang.org/x/net`, so
/// suffixes added between the two snapshots can differ — see the crate README.
fn icann_public_suffix(host: &str) -> Option<&str> {
    let suffix = psl::suffix(host.as_bytes())?;
    if suffix.typ() != Some(psl::Type::Icann) {
        return None;
    }
    std::str::from_utf8(suffix.as_bytes()).ok()
}

/// Keep only the last `labels` labels ("a.b.c.d.e.f" with 4 labels becomes "c.d.e.f").
///
/// This is the `strings.LastIndexFunc` walk of the old code: find the `labels`-th dot counted from
/// the end and start right after it.
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

/// `domainSuffixes`, longest first: `"a.b.com"` becomes `["a.b.com", "b.com", "com"]`.
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

/// `hex.DecodeString` for exactly [`HASH_SIZE`] bytes: both cases accepted, anything else rejected.
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

/// `dns.IsDomainName` over `dns.Fqdn(name)`.
fn is_domain_name(host: &str) -> bool {
    if host.is_empty() {
        return false;
    }
    let s = fqdn(host);
    let bytes = s.as_bytes();
    // miekg/dns packs names into a 255-byte buffer and counts it as 256 here.
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
                    // Leading dots are only legal for the root zone.
                    return false;
                }
                if was_dot {
                    // Two dots in a row.
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

/// `dns.Fqdn`.
fn fqdn(host: &str) -> Cow<'_, str> {
    if is_fqdn(host) {
        Cow::Borrowed(host)
    } else {
        Cow::Owned(format!("{host}."))
    }
}

/// `dns.IsFqdn`, including the "is the final dot escaped?" parity check.
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

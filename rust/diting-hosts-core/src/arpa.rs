//! Reverse-name parsing: `ParseIPFromArpa` before the move.
//!
//! Both the hosts resolver (`LookupPTR`) and the rewrite engine (`LookupPTR`) turned
//! `x.x.x.x.in-addr.arpa` / the 32-nibble `ip6.arpa` form back into an address. One copy is left,
//! here, and `ParseIPFromArpa` in Go is a call into it — the two callers can no longer disagree
//! about how many labels make a name, or which nibble is the low one.

use diting_go_compat::text::go_lower;

use crate::ip::{collapse_v6, parse_ip, Addr};

/// `ParseIPFromArpa`: `None` when the name is not a well-formed reverse name.
///
/// The name is lowercased and stripped of trailing dots first (`strings.ToLower(strings.Trim(…))`),
/// so `1.1.168.192.IN-ADDR.ARPA.` is fine. An IPv4 reverse name must have exactly four labels, an
/// IPv6 one exactly 32 single-nibble labels; anything else has no address behind it.
pub fn parse_arpa(name: &str) -> Option<Addr> {
    let lowered = go_lower(name);
    let trimmed = lowered.trim_end_matches('.').trim_start_matches('.');
    if let Some(prefix) = trimmed.strip_suffix(".in-addr.arpa") {
        let parts: Vec<&str> = prefix.split('.').collect();
        if parts.len() != 4 {
            return None;
        }
        // Reversed back to the dotted quad Go then ran through `net.ParseIP`, which is where a
        // leading zero or an empty label gets rejected.
        let text = format!("{}.{}.{}.{}", parts[3], parts[2], parts[1], parts[0]);
        return parse_ip(&text);
    }
    if let Some(prefix) = trimmed.strip_suffix(".ip6.arpa") {
        let nibbles: Vec<&str> = prefix.split('.').collect();
        if nibbles.len() != 32 {
            return None;
        }
        let mut bytes = [0u8; 16];
        for index in 0..16 {
            let low = nibble(nibbles[index * 2])?;
            let high = nibble(nibbles[index * 2 + 1])?;
            bytes[15 - index] = (high << 4) | low;
        }
        return Some(collapse_v6(bytes));
    }
    None
}

fn nibble(label: &str) -> Option<u8> {
    let bytes = label.as_bytes();
    if bytes.len() != 1 {
        return None;
    }
    match bytes[0] {
        b'0'..=b'9' => Some(bytes[0] - b'0'),
        b'a'..=b'f' => Some(bytes[0] - b'a' + 10),
        b'A'..=b'F' => Some(bytes[0] - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests;

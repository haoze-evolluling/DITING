//! The binary layout shared with `android/engine/mitm_sniffer_payload.go`.
//!
//! Little endian, a layout byte first, then the kind, then the hostname:
//!
//! ```text
//! sniff: u8 layout | u8 kind | u32 host_len | host bytes
//! ```
//!
//! The hostname is raw bytes (SNI or `Host` value), never assumed to be UTF-8. `kind` is one of
//! the three constants below; the Go caller rejects anything else.

/// Layout version of the payload below; `snifferPayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

/// The bytes were not a TLS ClientHello or a plaintext HTTP request.
pub const KIND_UNKNOWN: u8 = 0;
/// A TLS record; the host is the SNI, possibly empty.
pub const KIND_TLS: u8 = 1;
/// A plaintext HTTP request; the host is the `Host` value, possibly empty.
pub const KIND_HTTP: u8 = 2;

/// Encodes one classification.
pub fn encode(kind: u8, host: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(6 + host.len());
    out.push(LAYOUT_VERSION);
    out.push(kind);
    out.extend_from_slice(&(host.len() as u32).to_le_bytes());
    out.extend_from_slice(host);
    out
}

/// Decodes [`encode`]. Returns `(kind, host)`.
pub fn decode(data: &[u8]) -> Result<(u8, &[u8]), String> {
    if data.len() < 6 {
        return Err(format!(
            "payload is {} bytes, expected at least 6",
            data.len()
        ));
    }
    if data[0] != LAYOUT_VERSION {
        return Err(format!(
            "payload layout {}, expected {LAYOUT_VERSION}",
            data[0]
        ));
    }
    let kind = data[1];
    if kind > KIND_HTTP {
        return Err(format!("payload kind {kind} is not a sniff kind"));
    }
    let declared = u32::from_le_bytes([data[2], data[3], data[4], data[5]]) as usize;
    if declared != data.len() - 6 {
        return Err(format!(
            "payload declares {declared} host bytes, carries {}",
            data.len() - 6
        ));
    }
    Ok((kind, &data[6..]))
}

#[cfg(test)]
mod tests;

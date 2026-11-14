//! Outbound webhook signing and retry policy (A11).
//!
//! Automations and audit events can be mirrored to a user webhook. Two decisions must be identical
//! everywhere they are made, so they live here as pure functions: how a body is signed, and whether
//! and how long to wait before the next delivery attempt. The scheduler, the network and the secret
//! storage stay in the caller.
//!
//! Layout:
//! * [`sha256`] / [`hmac_sha256`] / [`sign`] — a dependency-free HMAC-SHA256 (no external crate, so
//!   the on-device build keeps its tiny dependency set).
//! * [`retry_after`] — exponential backoff capped by a maximum, with status-based retryability.
//! * [`ffi`] — the C ABI (`magic "DWH1" | abi`) a `dart:ffi` caller loads.

pub mod ffi;

pub use ffi::ABI_VERSION;

/// SHA-256 round constants.
const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn rotr(x: u32, n: u32) -> u32 {
    x.rotate_right(n)
}

/// SHA-256 digest of `data`.
pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.as_chunks::<64>().0 {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[4 * i],
                chunk[4 * i + 1],
                chunk[4 * i + 2],
                chunk[4 * i + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            let ch = (e & f) ^ (!e & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[4 * i..4 * i + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

/// HMAC-SHA256 of `msg` keyed by `key`.
pub fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut block = [0u8; 64];
    if key.len() > 64 {
        block[..32].copy_from_slice(&sha256(key));
    } else {
        block[..key.len()].copy_from_slice(key);
    }
    let mut inner_pad = [0x36u8; 64];
    let mut outer_pad = [0x5cu8; 64];
    for i in 0..64 {
        inner_pad[i] ^= block[i];
        outer_pad[i] ^= block[i];
    }

    let mut inner = inner_pad.to_vec();
    inner.extend_from_slice(msg);
    let inner_hash = sha256(&inner);

    let mut outer = outer_pad.to_vec();
    outer.extend_from_slice(&inner_hash);
    sha256(&outer)
}

/// Lowercase hex encoding.
pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(DIGITS[(byte >> 4) as usize] as char);
        out.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    out
}

/// The value a receiver verifies: `sha256=<hex hmac>` over `"{timestamp}.{body}"`.
///
/// Binding the timestamp into the MAC lets the receiver reject a replayed body with an old
/// signature; a plain body-only MAC could be replayed forever.
pub fn sign(secret: &str, body: &str, timestamp: i64) -> String {
    let signed = format!("{timestamp}.{body}");
    format!(
        "sha256={}",
        hex(&hmac_sha256(secret.as_bytes(), signed.as_bytes()))
    )
}

/// One retry decision.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RetryDecision {
    pub retry: bool,
    pub delay_ms: i64,
}

/// Whether to retry after the failed `attempt` (1-based) and how long to wait.
///
/// Permanent client errors (4xx) are not retried except 408 (timeout) and 429 (rate limited); 5xx,
/// 408, 429 and transport failures (no status) are retried with exponential backoff. The delay is
/// `base_ms * 2^(attempt-1)` capped at `max_ms`, so a broken endpoint cannot be hammered.
pub fn retry_after(
    attempt: i64,
    status: Option<i64>,
    base_ms: i64,
    max_ms: i64,
    max_attempts: i64,
) -> RetryDecision {
    let base = base_ms.max(0);
    let cap = max_ms.max(base);
    let limit = max_attempts.max(1);
    if attempt >= limit {
        return RetryDecision {
            retry: false,
            delay_ms: 0,
        };
    }
    let retryable = match status {
        None => true,
        Some(s) if s == 408 || s == 429 => true,
        Some(s) if s >= 500 => true,
        Some(_) => false,
    };
    if !retryable {
        return RetryDecision {
            retry: false,
            delay_ms: 0,
        };
    }
    let shift = (attempt - 1).clamp(0, 30) as u32;
    let delay = base.saturating_mul(1i64 << shift).min(cap);
    RetryDecision {
        retry: true,
        delay_ms: delay,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_matches_known_vector() {
        assert_eq!(
            hex(&sha256(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            hex(&sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn hmac_sha256_matches_known_vector() {
        // RFC-style test: key="key", data="The quick brown fox jumps over the lazy dog".
        assert_eq!(
            hex(&hmac_sha256(
                b"key",
                b"The quick brown fox jumps over the lazy dog"
            )),
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        );
    }

    #[test]
    fn signature_binds_timestamp_and_body() {
        let a = sign("secret", "{\"e\":1}", 1_700_000_000);
        let b = sign("secret", "{\"e\":1}", 1_700_000_001);
        assert!(a.starts_with("sha256="));
        assert_ne!(a, b);
        assert_eq!(a, sign("secret", "{\"e\":1}", 1_700_000_000));
    }

    #[test]
    fn retry_backoff_doubles_and_caps() {
        let d1 = retry_after(1, Some(500), 1000, 5000, 4);
        assert_eq!(
            d1,
            RetryDecision {
                retry: true,
                delay_ms: 1000
            }
        );
        let d2 = retry_after(2, Some(503), 1000, 5000, 4);
        assert_eq!(d2.delay_ms, 2000);
        let d3 = retry_after(3, None, 1000, 5000, 4);
        assert_eq!(d3.delay_ms, 4000);
        let d4 = retry_after(4, Some(500), 1000, 5000, 4);
        assert!(!d4.retry);
    }

    #[test]
    fn permanent_4xx_is_not_retried() {
        assert!(!retry_after(1, Some(400), 1000, 5000, 4).retry);
        assert!(!retry_after(1, Some(404), 1000, 5000, 4).retry);
        assert!(retry_after(1, Some(408), 1000, 5000, 4).retry);
        assert!(retry_after(1, Some(429), 1000, 5000, 4).retry);
    }
}

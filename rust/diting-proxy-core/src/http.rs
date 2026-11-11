//! The HTTP CONNECT request bytes.
//!
//! The old code built a `*http.Request` and let `Request.Write` serialize it, so the bytes are the
//! standard library's output for a CONNECT with an opaque URL: request line, `Host`, the default
//! `User-Agent` (`Go-http-client/1.1`, which `Request.Write` adds when the header is absent) and
//! then the remaining headers (only `Proxy-Authorization`, so the sorted order is trivial). The
//! blank line ends it.
//!
//! The reply still goes through Go's `http.ReadResponse`: it owns the `bufio` semantics the
//! migration must not change, and the status text it formats (`HTTP proxy returned %s`) is printed
//! verbatim.

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;

/// Serializes the CONNECT request Go used to build with `http.Request.Write`.
pub fn connect_request(target: &str, username: &str, password: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(160);
    out.extend_from_slice(b"CONNECT ");
    out.extend_from_slice(target.as_bytes());
    out.extend_from_slice(b" HTTP/1.1\r\nHost: ");
    out.extend_from_slice(target.as_bytes());
    out.extend_from_slice(b"\r\nUser-Agent: Go-http-client/1.1\r\n");
    if !username.is_empty() || !password.is_empty() {
        let token = STANDARD.encode(format!("{username}:{password}"));
        out.extend_from_slice(b"Proxy-Authorization: Basic ");
        out.extend_from_slice(token.as_bytes());
        out.extend_from_slice(b"\r\n");
    }
    out.extend_from_slice(b"\r\n");
    out
}

#[cfg(test)]
mod tests;

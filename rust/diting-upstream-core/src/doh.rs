//! DoH response classification and the one-shot retry rule.
//!
//! `queryDoHContext` treated 403 as "rate limited", anything other than 200 as a status error, and
//! retried exactly once when the transport error text contained `EOF` (the HTTP/2 connection was
//! reused after the server closed it, which `net/http` surfaces as `EOF` or `unexpected EOF`).
//!
//! The classification is here; the error texts (`DoH rate limited (403)`, `DoH status %d`), the
//! request construction and every `net/http` call stay in Go. Matching `EOF` inside the error text
//! is deliberately preserved: `errors.Is(err, io.EOF)` would miss the wrapped `unexpected EOF` and
//! change *which* failures get the retry.

/// What `queryDoHContext` makes of an HTTP status code.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusKind {
    /// The body is the DNS message.
    Ok,
    /// `DoH rate limited (403)`.
    RateLimited,
    /// `DoH status %d`.
    Other,
}

/// Classifies one DoH response status.
pub fn status_kind(status: i32) -> StatusKind {
    match status {
        200 => StatusKind::Ok,
        403 => StatusKind::RateLimited,
        _ => StatusKind::Other,
    }
}

/// Whether a failed attempt should be retried: only the first attempt, and only when the transport
/// error mentions `EOF`.
pub fn should_retry(attempt: u32, error_text: &str) -> bool {
    attempt == 1 && error_text.contains("EOF")
}

#[cfg(test)]
mod tests;

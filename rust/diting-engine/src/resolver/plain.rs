//! Plain DNS: UDP with the mobile retry shape, TCP framing and the truncation fallback.
//!
//! `resolver_plain.go` in Rust. Three details are easy to lose and all three are user-visible:
//!
//! * the UDP read gets a short first budget (`providerStats.UDPRetryDelay()`, 1.5 s cold) instead of
//!   the whole five-second query budget, because on a mobile link the first packet is often simply
//!   dropped — then the query is resent, at most [`TUNING::plain_retry_limit`] times, inside the
//!   budget. The deadline arithmetic itself is the kernel's
//!   ([`diting_upstream_core::framing`]).
//! * a `TC=1` UDP answer is a truncated answer (RFC 1035 §4.2.1): the query is retried over TCP, and
//!   the truncated UDP answer is only returned when TCP fails as well (a partially usable answer
//!   beats a SERVFAIL).
//! * plain TCP is prefixed with the 2-byte length, and a zero length is *not* rejected — Go read it
//!   as an empty response, which the caller's validation then failed.
//!
//! Both paths take the connect budget and the query budget from the tuning kernel, never from a
//! local constant.

use std::time::{Duration, Instant};

use diting_dns_core::message::{status, validate};
use diting_upstream_core::framing::{
    encode_length_prefixed, first_deadline_ns, is_truncated, retry_deadline_ns, tcp_response_length,
};
use diting_upstream_core::tuning::TUNING;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::timeout_at;

use crate::resolver::dial::Dialer;

/// The plain UDP read buffer (`make([]byte, 4096)`).
const UDP_BUFFER: usize = 4096;

/// `queryPlainContext`: UDP first, TCP when the answer is truncated.
///
/// `retry_delay_ns` is the provider's adaptive retry interval (`providerStats.UDPRetryDelay()`),
/// which the scheduler's statistics already computed before the attempt started.
pub async fn query(
    dialer: &Dialer,
    host: &str,
    port: &str,
    query: &[u8],
    retry_delay_ns: i64,
) -> Result<Vec<u8>, String> {
    // Go: `if !outbound.SupportsUDP() { return queryPlainTCPContext(...) }`. An HTTP CONNECT proxy
    // has no datagram mode, so plain DNS has to ride a framed TCP stream instead of failing every
    // query.
    if !dialer.resolver_udp_supported() {
        return query_tcp(dialer, host, port, query).await;
    }
    let target = dialer.resolve(host, port).await?;
    query_udp(dialer, host, port, target, query, retry_delay_ns).await
}

async fn query_udp(
    dialer: &Dialer,
    host: &str,
    port: &str,
    target: std::net::SocketAddr,
    query: &[u8],
    retry_delay_ns: i64,
) -> Result<Vec<u8>, String> {
    // Direct or SOCKS5 UDP ASSOCIATE, depending on the outbound scope: the resolver's own
    // upstream queries follow the proxy under `scope:"all"`, like Go's `resolverOutbound()`.
    let socket = dialer
        .udp_transport(target)
        .await
        .map_err(|error| format!("plain dial: {error}"))?;

    let now = Instant::now();
    let now_ns = crate::resolver::now_ns();
    let budget = Duration::from_nanos(TUNING.query_timeout_plain_ns.max(1) as u64);
    let deadline_ns = now_ns + budget.as_nanos() as i64;
    let initial_ns = if retry_delay_ns > 0 {
        retry_delay_ns
    } else {
        TUNING.plain_retry_default_ns
    }
    .clamp(1, budget.as_nanos() as i64);

    let mut read_deadline_ns = first_deadline_ns(now_ns, initial_ns, deadline_ns);
    socket.send(query).await?;

    let mut buffer = vec![0u8; UDP_BUFFER];
    let mut last_error = String::new();
    // `for retry := 0; err != nil && retry < plainRetryLimit; retry++`: the retry index survives the
    // iteration, so the second resend gets the whole remaining budget and no more.
    let mut retry = 0u32;
    let received = loop {
        match timeout_at(
            deadline_at(now, read_deadline_ns - now_ns),
            socket.recv(&mut buffer),
        )
        .await
        {
            Ok(Ok(read)) => break Some(read),
            Ok(Err(error)) => last_error = error,
            Err(_) => last_error = "plain read: timed out".to_string(),
        }

        if retry >= TUNING.plain_retry_limit.max(0) as u32 {
            break None;
        }
        let Some(next) =
            retry_deadline_ns(crate::resolver::now_ns(), initial_ns, deadline_ns, retry)
        else {
            break None;
        };
        retry += 1;
        read_deadline_ns = next;
        if let Err(error) = socket.send(query).await {
            last_error = error;
            break None;
        }
    };

    let Some(read) = received else {
        return Err(last_error);
    };
    let response = &buffer[..read];
    let validation = validate(query, response);
    if validation.status != status::ACCEPTED {
        return Err(invalid_answer(&validation));
    }

    if is_truncated(response) {
        // Keep the truncated answer only when TCP also failed: reporting a hard error would turn a
        // partially usable answer into SERVFAIL.
        if let Ok(full) = query_tcp(dialer, host, port, query).await {
            return Ok(full);
        }
    }

    Ok(response.to_vec())
}

/// `queryPlainTCPContext`: one framed request, one framed response.
async fn query_tcp(
    dialer: &Dialer,
    host: &str,
    port: &str,
    query: &[u8],
) -> Result<Vec<u8>, String> {
    let mut stream = dialer
        .connect_tcp(host, port)
        .await
        .map_err(|error| format!("plain TCP dial: {error}"))?;

    let budget = Duration::from_nanos(TUNING.query_timeout_plain_ns.max(1) as u64);
    let outcome = timeout_at(
        tokio::time::Instant::now() + budget,
        exchange_tcp(&mut stream, query),
    )
    .await;
    match outcome {
        Ok(result) => result,
        Err(_) => Err("plain TCP read: timed out".to_string()),
    }
}

async fn exchange_tcp(stream: &mut TcpStream, query: &[u8]) -> Result<Vec<u8>, String> {
    let framed = encode_length_prefixed(query);
    stream
        .write_all(&framed)
        .await
        .map_err(|error| format!("plain TCP write: {error}"))?;

    let mut header = [0u8; 2];
    stream
        .read_exact(&mut header)
        .await
        .map_err(|error| format!("plain TCP read length: {error}"))?;
    let Some(length) = tcp_response_length(&header) else {
        return Err("plain TCP read length: unreadable header".to_string());
    };

    let mut response = vec![0u8; length];
    stream
        .read_exact(&mut response)
        .await
        .map_err(|error| format!("plain TCP read: {error}"))?;
    Ok(response)
}

/// The text of a rejected answer: the rcode name when the upstream answered at all, the status code
/// otherwise (which is the wording stage 1's log rows already use).
pub fn invalid_answer(validation: &diting_dns_core::message::Validation) -> String {
    if validation.status == status::UPSTREAM_RCODE {
        return format!("upstream returned {}", rcode_name(validation.rcode));
    }
    format!("invalid upstream answer (status {})", validation.status)
}

/// `dns.RcodeToString` for the codes the engine can see, with the numeric fallback.
pub fn rcode_name(rcode: u16) -> String {
    match rcode {
        0 => "NOERROR".to_string(),
        1 => "FORMERR".to_string(),
        2 => "SERVFAIL".to_string(),
        3 => "NXDOMAIN".to_string(),
        4 => "NOTIMP".to_string(),
        5 => "REFUSED".to_string(),
        other => format!("RCODE{other}"),
    }
}

/// A `tokio` deadline from the nanosecond offsets the kernel's arithmetic produced.
fn deadline_at(origin: Instant, offset_ns: i64) -> tokio::time::Instant {
    let origin = tokio::time::Instant::from_std(origin);
    if offset_ns <= 0 {
        origin
    } else {
        origin + Duration::from_nanos(offset_ns as u64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rcode_names_match_the_go_table() {
        assert_eq!(rcode_name(3), "NXDOMAIN");
        assert_eq!(rcode_name(5), "REFUSED");
        assert_eq!(rcode_name(9), "RCODE9");
    }

    #[test]
    fn an_upstream_rcode_reads_like_the_go_error() {
        let validation = diting_dns_core::message::Validation {
            status: status::UPSTREAM_RCODE,
            rcode: 5,
        };
        assert_eq!(invalid_answer(&validation), "upstream returned REFUSED");
    }

    #[test]
    fn a_status_only_rejection_keeps_the_stage_one_wording() {
        let validation = diting_dns_core::message::Validation {
            status: status::TRANSACTION_MISMATCH,
            rcode: 0,
        };
        assert_eq!(
            invalid_answer(&validation),
            "invalid upstream answer (status 5)"
        );
    }
}

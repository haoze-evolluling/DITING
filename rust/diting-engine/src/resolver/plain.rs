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

const UDP_BUFFER: usize = 4096;

pub async fn query(
    dialer: &Dialer,
    host: &str,
    port: &str,
    query: &[u8],
    retry_delay_ns: i64,
) -> Result<Vec<u8>, String> {
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
        if let Ok(full) = query_tcp(dialer, host, port, query).await {
            return Ok(full);
        }
    }

    Ok(response.to_vec())
}

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

pub fn invalid_answer(validation: &diting_dns_core::message::Validation) -> String {
    if validation.status == status::UPSTREAM_RCODE {
        return format!("upstream returned {}", rcode_name(validation.rcode));
    }
    format!("invalid upstream answer (status {})", validation.status)
}

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

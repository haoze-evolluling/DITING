//! Non-DNS relay: the flow's client side ↔ the outbound transport (stage 4a).
//!
//! `tcp_stack_handlers.go`'s `bidiCopyFlow` / `relayUDPFlow` and `engine_full_tunnel.go`'s
//! `newFullPassthroughTcpHandler` / `newFullTunnelUdpHandler`, reduced to what the channel-based
//! flow interface needs:
//!
//! * TCP: one task per direction. The client half-close (`Inbound::Eof`) becomes `shutdown()` on the
//!   upstream socket, so a client that writes a request and shuts down its write side still gets the
//!   response; upstream EOF becomes `Event::CloseWrite` back to the stack.
//! * UDP: one task per 4-tuple, `select!`ing between the client's datagrams and the upstream socket.
//!   The idle window is 30 s and rolls on every datagram, like `relayUDPFlow`'s deadlines.
//!
//! Traffic accounting keeps `countingConn`'s direction: bytes read from the client are `tx` (the
//! session records those when it drains the stack), bytes read from the upstream are `rx`.
//!
//! A dial failure is logged and turns into `Event::Abort` (TCP) or an exit (UDP); it also increments
//! [`TunnelCounters::relay_unavailable`] so `getStats` distinguishes "no relay" from "no traffic".

use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, Semaphore};

use crate::engine::{now_ms, Engine};
use crate::netstack::{self, TcpKey};
use crate::outbound::{Outbound, Route};
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::queue::{Event, Events};
use crate::tunnel::stats::TunnelCounters;
use diting_telemetry_core::LogItem;

/// The TCP relay buffer (`tcpCopyBufferSize`).
pub const TCP_BUFFER: usize = 32 * 1024;
/// The UDP relay buffer (`udpRelayBufSize`): QUIC and EDNS fit, fragmented >16 KiB does not.
pub const UDP_BUFFER: usize = 16 * 1024;
/// `defaultUDPIdleTimeout`.
pub const UDP_IDLE: Duration = Duration::from_secs(30);

/// `hostPeekSize`: how much of the first client burst the host sniffer may see.
const HOST_PEEK_SIZE: usize = 4 * 1024;
/// `hostPeekTimeout`: a TLS ClientHello / HTTP request arrives immediately; a slow one just relays.
const HOST_PEEK_TIMEOUT: Duration = Duration::from_secs(3);

/// Ports whose first client burst carries a hostname we can read without decrypting.
fn is_sniffable_port(port: u16) -> bool {
    port == 443 || port == 80
}

/// Peek the first client burst (up to `HOST_PEEK_SIZE`) without losing it, so the caller can write
/// it upstream after a normal dial. Returns the bytes and whether the client already half-closed.
async fn peek_client(inbound: &mut mpsc::Receiver<Inbound>, timeout: Duration) -> (Vec<u8>, bool) {
    let mut peeked = Vec::new();
    match tokio::time::timeout(timeout, inbound.recv()).await {
        Ok(Some(Inbound::Data(data))) => peeked.extend_from_slice(&data),
        Ok(Some(Inbound::Eof)) | Ok(None) => return (peeked, true),
        // A slow client, or a protocol where the server speaks first: relay without sniffing.
        Err(_) => return (peeked, false),
    }
    // Take whatever else is already queued so a split ClientHello still parses.
    while peeked.len() < HOST_PEEK_SIZE {
        match inbound.try_recv() {
            Ok(Inbound::Data(data)) => peeked.extend_from_slice(&data),
            Ok(Inbound::Eof) => return (peeked, true),
            Err(_) => break,
        }
    }
    (peeked, false)
}

/// The SNI / HTTP `Host` named by a peeked burst, lowercased and trailing-dot trimmed, if any.
fn sniff_host(bytes: &[u8]) -> Option<String> {
    if bytes.is_empty() {
        return None;
    }
    let sniffed = diting_sniffer_core::classify(bytes);
    if sniffed.host.is_empty() {
        return None;
    }
    let host = String::from_utf8_lossy(&sniffed.host)
        .trim()
        .trim_end_matches('.')
        .to_ascii_lowercase();
    if host.is_empty() {
        None
    } else {
        Some(host)
    }
}

/// Records a connection-layer block with the log shape the UI reads (`blocked == true`).
fn log_conn_block(engine: &Engine, key: &TcpKey, uid: i32, host: &str, reason: &str) {
    let dest = netstack::socket_addr(key.local);
    engine.logs().push(LogItem {
        domain: host.to_string(),
        blocked: true,
        query_type: 0,
        response_time_ms: 0,
        app_name: engine.display_name(uid),
        resolved_ips: dest.to_string(),
        blocked_by: format!("conn:host:{reason}"),
        error_message: String::new(),
        cached: false,
        timestamp_ms: now_ms(),
        ttl: 0,
    });
}

/// One TCP flow: dial, then copy both directions with half-close.
pub async fn relay_tcp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
    key: TcpKey,
    uid: i32,
    mut inbound: mpsc::Receiver<Inbound>,
    credit: Arc<Semaphore>,
) {
    // Connection-layer host blocking: an app that resolved through its own HTTPDNS/DoH or a
    // hard-coded IP never reaches the DNS pipeline, but its TLS ClientHello / HTTP Host still names
    // the ad host. Sniff :80/:443 only, only while a rule snapshot is published, and never decrypt —
    // this is a plain pass/fail gate ahead of the opaque relay. Fail-open: no host, no snapshot or a
    // slow first byte all relay exactly as before.
    let (peeked, saw_eof) =
        if is_sniffable_port(key.local.port) && engine.policy().filtering_active() {
            let (bytes, eof) = peek_client(&mut inbound, HOST_PEEK_TIMEOUT).await;
            if let Some(host) = sniff_host(&bytes) {
                let app = engine.app_name(uid);
                if let Some(verdict) = engine.policy().evaluate(&host, &app, 0) {
                    if verdict.blocked {
                        log_conn_block(&engine, &key, uid, &host, &verdict.reason);
                        events.push_command(Event::Abort(key));
                        return;
                    }
                }
            }
            (bytes, eof)
        } else {
            (Vec::new(), false)
        };

    let target = netstack::socket_addr(key.local);
    let outbound = engine.outbound();
    let route = outbound.route_for(uid);
    let stream = match outbound.dial_tcp(route, target).await {
        Ok(stream) => stream,
        Err(error) => {
            counters
                .relay_unavailable
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            engine.log_error(&format!(
                "[TcpStack] upstream dial {target} failed: {error}"
            ));
            events.push_command(Event::Abort(key));
            return;
        }
    };

    let (mut upstream_read, mut upstream_write) = stream.into_split();

    let client_to_upstream = tokio::spawn(async move {
        // Replay the sniffed bytes first, then keep copying. `Some(Inbound::Eof)` is the client's
        // FIN: send ours but keep reading the response.
        if !peeked.is_empty() && upstream_write.write_all(&peeked).await.is_err() {
            return false;
        }
        if !saw_eof {
            while let Some(Inbound::Data(data)) = inbound.recv().await {
                if upstream_write.write_all(&data).await.is_err() {
                    return false;
                }
            }
        }
        let _ = upstream_write.shutdown().await;
        true
    });

    let downstream_engine = Arc::clone(&engine);
    let downstream_events = Arc::clone(&events);
    let upstream_to_client = tokio::spawn(async move {
        let mut buffer = vec![0u8; TCP_BUFFER];
        loop {
            match upstream_read.read(&mut buffer).await {
                Ok(0) => break,
                Ok(read) => {
                    downstream_engine.traffic().record(uid, 0, read as i64);
                    // Reserve write-backlog budget before queueing. This is the backpressure the Go
                    // engine got from a blocking `Write`: when the client stops draining the socket
                    // the reservation blocks here and we stop reading upstream instead of piling up
                    // (and then resetting) an unbounded backlog.
                    match credit.acquire_many(read as u32).await {
                        Ok(permit) => permit.forget(),
                        // The flow was torn down while we waited: stop reading upstream.
                        Err(_) => break,
                    }
                    downstream_events.push_command(Event::Write(
                        key,
                        buffer[..read].to_vec(),
                        Some(Arc::clone(&credit)),
                    ));
                }
                Err(_) => break,
            }
        }
        downstream_events.push_command(Event::CloseWrite(key));
    });

    let (forwarded, _) = tokio::join!(client_to_upstream, upstream_to_client);
    if !forwarded.unwrap_or(false) {
        events.push_command(Event::Abort(key));
    }
}

/// One UDP 4-tuple: dial, then relay both directions until the idle window expires.
pub async fn relay_udp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
    key: TcpKey,
    uid: i32,
    mut inbound: mpsc::Receiver<Vec<u8>>,
) {
    let target = netstack::socket_addr(key.local);
    let outbound: Outbound = engine.outbound();
    // The scope decides per UID: a flow that is *not* proxied goes direct and its UDP must keep
    // working even when the proxy itself is HTTP CONNECT (which has no datagram mode). Only a flow
    // that actually rides the proxy is rejected for the missing UDP support.
    let route: Route = outbound.route_for(uid);
    if route == Route::Proxy && !outbound.supports_udp() {
        counters
            .relay_unavailable
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        engine.log_error(&format!(
            "[FullTunnel] UDP {target}: outbound proxy does not support UDP"
        ));
        events.push_command(Event::UdpExpire(key));
        return;
    }
    let transport = match outbound.dial_udp(route, target).await {
        Ok(transport) => transport,
        Err(error) => {
            counters
                .relay_unavailable
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            engine.log_error(&format!("[FullTunnel] UDP dial {target}: {error}"));
            events.push_command(Event::UdpExpire(key));
            return;
        }
    };

    let mut buffer = vec![0u8; UDP_BUFFER];
    loop {
        tokio::select! {
            outgoing = inbound.recv() => {
                match outgoing {
                    Some(payload) => {
                        if let Err(error) = transport.send(&payload).await {
                            engine.log_error(&format!("[FullTunnel] UDP {target}: {error}"));
                            break;
                        }
                    }
                    // The session dropped the channel: the flow is gone.
                    None => break,
                }
            }
            incoming = transport.recv(&mut buffer) => {
                match incoming {
                    Ok(0) => {}
                    Ok(read) => {
                        engine.traffic().record(uid, 0, read as i64);
                        events.push_command(Event::Datagram {
                            local: key.local,
                            peer: key.remote,
                            payload: buffer[..read].to_vec(),
                        });
                    }
                    Err(error) => {
                        engine.log_error(&format!("[FullTunnel] UDP {target}: {error}"));
                        break;
                    }
                }
            }
            // Rolling idle: recreated every iteration, so it only fires after 30 s of silence.
            _ = tokio::time::sleep(UDP_IDLE) => break,
        }
    }
    events.push_command(Event::UdpExpire(key));
}

#[cfg(test)]
mod tests {
    use super::{is_sniffable_port, sniff_host};

    #[test]
    fn only_80_and_443_are_sniffed() {
        assert!(is_sniffable_port(80));
        assert!(is_sniffable_port(443));
        assert!(!is_sniffable_port(53));
        assert!(!is_sniffable_port(8080));
    }

    #[test]
    fn http_host_is_extracted_and_lowercased() {
        let request = b"GET /ad.js HTTP/1.1\r\nHost: Ads.Example\r\n\r\n";
        assert_eq!(sniff_host(request).as_deref(), Some("ads.example"));
    }

    #[test]
    fn unknown_and_empty_have_no_host() {
        assert!(sniff_host(b"").is_none());
        assert!(sniff_host(b"\x00\x01\x02not-a-handshake").is_none());
    }
}

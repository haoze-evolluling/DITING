//! DNS over the TUN: `handleDNSOverUDP` / `handleDNSOverTCP` from `engine_dns_transport.go`.
//!
//! The pipeline itself is unchanged — [`crate::dns::serve_for_app`] is the same `serveDNS` the
//! standalone server runs, with the flow's package name in the log row. What is new is the transport:
//! UDP answers one datagram at a time; TCP is the 2-byte length framing with a 15 s idle window, and
//! its answers are queued back into the stack through the session's command queue.
//!
//! Both paths count bytes into [`diting_telemetry_core::TrafficTracker`] the way Go's
//! `countingConn` did: the query is `tx`, the answer is `rx`, attributed to the flow's UID. The UID
//! is resolved once when the flow opens, not per datagram.

use std::sync::Arc;
use std::time::Duration;

use tokio::sync::mpsc;

use crate::engine::Engine;
use crate::netstack::{TcpKey, UdpDatagram};
use crate::tunnel::gate::FlowContext;
use crate::tunnel::queue::{Event, Events};

/// `dnsTCPIdleTimeout` / `dnsUDPIdleTimeout`.
pub const DNS_IDLE_TIMEOUT: Duration = Duration::from_secs(15);

/// `dns.MaxMsgSize`: a length prefix past this is not a DNS message, and the Go code never read
/// more than 64 KiB either. The stack's own buffers are far smaller, so this only guards the parser.
const MAX_FRAME: usize = 4096;

/// What the session feeds a TCP flow's handler.
#[derive(Debug)]
pub enum Inbound {
    /// Bytes the client sent (already counted as `tx`).
    Data(Vec<u8>),
    /// The client sent FIN.
    Eof,
}

/// One UDP datagram: ask the pipeline, answer from the original destination.
pub async fn serve_udp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    datagram: UdpDatagram,
    context: FlowContext,
) {
    let Some(response) = crate::dns::serve_for_app(&engine, &datagram.payload, &context.app).await
    else {
        return;
    };
    engine
        .traffic()
        .record(context.uid, 0, response.len() as i64);
    events.push_command(Event::Datagram {
        local: datagram.local,
        peer: datagram.peer,
        payload: response,
    });
}

/// One TCP connection carrying length-prefixed DNS messages until the client leaves or idles out.
pub async fn serve_tcp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    key: TcpKey,
    mut inbound: mpsc::Receiver<Inbound>,
    context: FlowContext,
) {
    let mut buffer: Vec<u8> = Vec::new();
    loop {
        let next = match tokio::time::timeout(DNS_IDLE_TIMEOUT, inbound.recv()).await {
            // Idle: the Go handler returned and closed the connection.
            Err(_) => break,
            Ok(None) => break,
            Ok(Some(Inbound::Eof)) => break,
            Ok(Some(Inbound::Data(data))) => data,
        };
        buffer.extend_from_slice(&next);

        while let Some(query) = take_frame(&mut buffer) {
            let Some(response) = crate::dns::serve_for_app(&engine, &query, &context.app).await
            else {
                continue;
            };
            let mut framed = Vec::with_capacity(2 + response.len());
            framed.extend_from_slice(&(response.len() as u16).to_be_bytes());
            framed.extend_from_slice(&response);
            engine.traffic().record(context.uid, 0, framed.len() as i64);
            events.push_command(Event::Write(key, framed, None));
        }
    }
    // The client is gone (or idle): close the write side so the peer sees EOF, then let the stack
    // release the socket when the FIN exchange completes.
    events.push_command(Event::CloseWrite(key));
}

/// Pops one complete `[u16 length][message]` frame, or `None` while more bytes are needed.
///
/// A zero-length frame is skipped (Go's `if msgLen == 0 { continue }`), and an oversized length
/// discards the connection's buffer: no DNS message is that large, and trusting it would let a
/// peer make the handler wait for 64 KiB it will never send.
pub fn take_frame(buffer: &mut Vec<u8>) -> Option<Vec<u8>> {
    loop {
        if buffer.len() < 2 {
            return None;
        }
        let length = usize::from(u16::from_be_bytes([buffer[0], buffer[1]]));
        if length == 0 {
            buffer.drain(..2);
            continue;
        }
        if length > MAX_FRAME {
            buffer.clear();
            return None;
        }
        if buffer.len() < 2 + length {
            return None;
        }
        let frame = buffer[2..2 + length].to_vec();
        buffer.drain(..2 + length);
        return Some(frame);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn framed(message: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&(message.len() as u16).to_be_bytes());
        out.extend_from_slice(message);
        out
    }

    #[test]
    fn a_frame_is_taken_only_when_it_is_complete() {
        let mut buffer = framed(b"abc");
        let partial = buffer.split_off(3);
        assert_eq!(take_frame(&mut buffer), None);
        buffer.extend_from_slice(&partial);
        assert_eq!(take_frame(&mut buffer), Some(b"abc".to_vec()));
        assert!(buffer.is_empty());
    }

    #[test]
    fn two_frames_in_one_chunk_are_both_read() {
        let mut buffer = framed(b"one");
        buffer.extend_from_slice(&framed(b"two"));
        assert_eq!(take_frame(&mut buffer), Some(b"one".to_vec()));
        assert_eq!(take_frame(&mut buffer), Some(b"two".to_vec()));
        assert_eq!(take_frame(&mut buffer), None);
    }

    #[test]
    fn a_zero_length_frame_is_skipped() {
        let mut buffer = vec![0, 0];
        buffer.extend_from_slice(&framed(b"x"));
        assert_eq!(take_frame(&mut buffer), Some(b"x".to_vec()));
    }

    #[test]
    fn an_oversized_length_discards_the_buffer() {
        let mut buffer = (MAX_FRAME as u16 + 1).to_be_bytes().to_vec();
        assert_eq!(take_frame(&mut buffer), None);
        assert!(buffer.is_empty());
    }
}

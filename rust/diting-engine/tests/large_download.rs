//! A large downstream transfer through the full tunnel must arrive byte-for-byte.
//!
//! Regression guard for the Rust netstack: the Go engine's blocking `Write` gave the downstream
//! copy natural backpressure, so a multi-megabyte response (a QQ/HTTP file download) simply waited
//! when the client was momentarily slow. The channel-based Rust rewrite reads the upstream as fast
//! as it can and only bounds the unwritten bytes at the socket, so without backpressure a download
//! larger than the bound is reset mid-stream and the client sees a truncated file.
//!
//! This drives the production `Session` through [`MemoryLink`] with a loopback upstream that pushes
//! `TOTAL` bytes and a hand-written client that ACKs (and reads) every segment, which is exactly the
//! shape a browser/QQ download has.

mod support;

use std::net::TcpListener;
use std::sync::Arc;
use std::time::{Duration, Instant};

use diting_engine::tunnel::MemoryLink;
use diting_engine::Engine;
use smoltcp::wire::{IpEndpoint, TcpControl};

use support::tunnel::wait_tcp;
use support::wire;

const APP: [u8; 4] = [10, 0, 0, 2];
const APP_PORT: u16 = 40123;
/// Two mebibytes: comfortably past any per-flow write bound, so a missing-backpressure truncation
/// shows up as a short read rather than a slow-but-complete transfer.
const TOTAL: usize = 2 * 1024 * 1024;

fn engine_for(upstream: std::net::SocketAddr) -> Arc<Engine> {
    let engine = Arc::new(Engine::new());
    let config = support::config_json(
        "single",
        &[support::provider_json(
            "p1",
            "PLAIN",
            &upstream.to_string(),
            "",
        )],
        None,
    );
    engine
        .apply_dns_config(&config)
        .expect("the config applies");
    engine.set_filter_dns(true);
    engine
}

/// A loopback server that pushes `TOTAL` patterned bytes on accept and then half-closes.
fn spawn_download_server(total: usize) -> std::net::SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind the download server");
    let address = listener.local_addr().expect("addr");
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            std::thread::spawn(move || {
                let chunk = vec![0x5au8; 16 * 1024];
                let mut sent = 0usize;
                while sent < total {
                    let take = (total - sent).min(chunk.len());
                    if std::io::Write::write_all(&mut stream, &chunk[..take]).is_err() {
                        return;
                    }
                    sent += take;
                }
                let _ = std::io::Write::flush(&mut stream);
                let _ = stream.shutdown(std::net::Shutdown::Write);
                // Keep the read half open until the client's FIN, mirroring a real HTTP server.
                let mut sink = [0u8; 1024];
                let _ = std::io::Read::read(&mut stream, &mut sink);
            });
        }
    });
    address
}

/// The next TCP segment the stack emits towards `client`, skipping anything else.
fn next_segment(
    link: &MemoryLink,
    server: IpEndpoint,
    client: IpEndpoint,
    timeout: Duration,
) -> Option<wire::TcpSegment> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let packet = link.wait_outbound(Duration::from_millis(50))?;
        if let Some(segment) = wire::parse_tcp(&packet) {
            if segment.src == server && segment.dst == client {
                return Some(segment);
            }
        }
    }
    None
}

fn download(engine: &Arc<Engine>, link: &Arc<MemoryLink>, server: IpEndpoint) -> usize {
    let client = wire::endpoint_v4(APP, APP_PORT);
    let mut seq = 5_000u32;

    link.feed(wire::emit_tcp(
        client,
        server,
        seq,
        None,
        TcpControl::Syn,
        &[],
    ));
    seq += 1;
    let syn_ack = wait_tcp(link, |segment| {
        segment.is_syn_ack() && segment.src == server && segment.dst == client
    })
    .expect("a SYN-ACK from the download server");
    let mut ack = syn_ack.seq_number + 1;
    link.feed(wire::emit_tcp(
        client,
        server,
        seq,
        Some(ack),
        TcpControl::None,
        &[],
    ));

    let mut received = 0usize;
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        let Some(segment) = next_segment(link, server, client, Duration::from_secs(3)) else {
            break;
        };
        if !segment.payload.is_empty() {
            // The link is lossless, so segments arrive in order; still guard against a retransmit.
            if segment.seq_number == ack {
                ack = ack.wrapping_add(segment.payload.len() as u32);
                received += segment.payload.len();
            }
            link.feed(wire::emit_tcp(
                client,
                server,
                seq,
                Some(ack),
                TcpControl::None,
                &[],
            ));
        }
        if segment.is_fin() {
            ack = ack.wrapping_add(1);
            link.feed(wire::emit_tcp(
                client,
                server,
                seq,
                Some(ack),
                TcpControl::None,
                &[],
            ));
            break;
        }
    }
    let _ = engine;
    received
}

#[test]
fn a_two_mebibyte_download_arrives_whole() {
    let (upstream, _queries) = support::spawn_udp_upstream([1, 2, 3, 4], false);
    let engine = engine_for(upstream);
    let link = Arc::new(MemoryLink::new(1400));
    engine
        .start_full_with_link(link.clone())
        .expect("the session starts");

    let listener = spawn_download_server(TOTAL);
    let server = match listener {
        std::net::SocketAddr::V4(v4) => wire::endpoint_v4(v4.ip().octets(), listener.port()),
        std::net::SocketAddr::V6(_) => unreachable!("the server binds IPv4"),
    };

    let received = download(&engine, &link, server);
    let tun = engine.tun_document().expect("the tun document");

    engine.stop_full();

    assert_eq!(
        tun["shortWrites"],
        serde_json::json!(0),
        "a healthy download must not be reset by the write-backlog cap: tun={tun}"
    );
    assert_eq!(
        received, TOTAL,
        "the whole 2 MiB body must cross the tunnel, got {received} bytes; tun={tun}"
    );
}

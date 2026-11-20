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
                let mut sink = [0u8; 1024];
                let _ = std::io::Read::read(&mut stream, &mut sink);
            });
        }
    });
    address
}

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

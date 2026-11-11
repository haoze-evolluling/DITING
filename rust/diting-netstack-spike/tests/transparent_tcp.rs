//! The TCP half of the spike: does `smoltcp` accept a connection to an arbitrary destination?
//!
//! Every test feeds hand-crafted client packets. The stack is configured with the *unspecified*
//! address (`0.0.0.0` / `::`, prefix 0), so any passing case proves that
//! `Interface::set_any_ip(true)` plus a per-flow `listen(destination)` really is a transparent
//! proxy: `smoltcp` answers for addresses it was never told about.

mod support;

use diting_netstack_spike::{Limits, Netstack};
use smoltcp::socket::tcp;
use smoltcp::wire::TcpControl;
use support::{endpoint_v4, endpoint_v6, Harness, TcpClient};

#[test]
fn interface_stays_transparent() {
    let net = Netstack::new(Limits::default());
    assert!(
        net.any_ip(),
        "any_ip is the switch that lets ingress for unknown destinations through"
    );
}

/// The negative control: without `set_any_ip` the same SYN is dropped on ingress by the address
/// check, which is exactly the limitation that made this spike necessary.
#[test]
fn without_any_ip_foreign_destinations_are_dropped() {
    let mut harness = Harness::default();
    harness.net.set_any_ip(false);
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 39_999),
        endpoint_v4([93, 184, 216, 34], 443),
    );

    let out = harness.feed(client.syn());
    assert!(
        harness.tcp_segments(&out).is_empty(),
        "an address the interface does not own never reaches the socket layer"
    );
    // The socket is created by the SYN preprocessing, but the interface drops the packet, so it
    // stays in `Listen` until the idle sweep reaps it. Nothing reaches the client.
    let flow = harness
        .net
        .tcp_flow(&client.key())
        .expect("the socket exists");
    assert_eq!(flow.state(), tcp::State::Listen);
    assert_eq!(flow.rx_bytes, 0);
}

#[test]
fn accepts_any_ipv4_destination() {
    let mut harness = Harness::default();
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 40_000),
        endpoint_v4([93, 184, 216, 34], 443),
    );

    let syn_ack = client.connect(&mut harness);
    assert_eq!(syn_ack.src, client.remote, "the destination is the source");
    assert_eq!(syn_ack.dst, client.local);

    let flow = harness
        .net
        .tcp_flow(&client.key())
        .expect("a flow exists for the 4-tuple");
    assert_eq!(flow.state(), tcp::State::Established);
    assert_eq!(
        flow.key.local, client.remote,
        "the original destination is kept"
    );
    assert_eq!(harness.net.stats().tcp_accepted, 1);
    assert_eq!(harness.net.stats().tcp_rejected, 0);
}

#[test]
fn accepts_any_ipv6_destination() {
    let mut harness = Harness::default();
    let mut client = TcpClient::new(
        endpoint_v6([0xfd, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2], 40_001),
        endpoint_v6(
            [0x26, 6, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11],
            8443,
        ),
    );

    let syn_ack = client.connect(&mut harness);
    assert_eq!(syn_ack.src, client.remote);
    assert_eq!(syn_ack.dst, client.local);
    assert_eq!(
        harness.net.tcp_flow(&client.key()).unwrap().state(),
        tcp::State::Established
    );
}

#[test]
fn one_flow_per_4_tuple_even_on_a_shared_destination_port() {
    let mut harness = Harness::default();
    let dns_tls = endpoint_v4([1, 1, 1, 1], 853);
    let mut first = TcpClient::new(endpoint_v4([10, 0, 0, 2], 41_000), dns_tls);
    let mut second = TcpClient::new(endpoint_v4([10, 0, 0, 2], 41_001), dns_tls);

    first.connect(&mut harness);
    second.connect(&mut harness);

    assert_eq!(harness.net.tcp_flow_count(), 2);
    assert_eq!(
        harness.net.tcp_flow(&first.key()).unwrap().key.local,
        dns_tls
    );
    assert_eq!(
        harness.net.tcp_flow(&second.key()).unwrap().key.local,
        dns_tls
    );
    assert_eq!(harness.net.stats().tcp_accepted, 2);
}

#[test]
fn relays_payload_in_both_directions() {
    let mut harness = Harness::default();
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 42_000),
        endpoint_v4([151, 101, 1, 69], 80),
    );
    client.connect(&mut harness);

    let request = b"GET / HTTP/1.1\r\nHost: example.test\r\n\r\n";
    let out = harness.feed(client.data(request));
    assert!(
        harness
            .tcp_segments(&out)
            .iter()
            .all(|segment| segment.payload.is_empty()),
        "client data is only acknowledged, never echoed"
    );

    let mut buffer = vec![0u8; 256];
    let read = harness.net.tcp_read(&client.key(), &mut buffer);
    assert_eq!(&buffer[..read], request);
    assert_eq!(
        harness.net.tcp_flow(&client.key()).unwrap().rx_bytes,
        request.len() as u64
    );

    let response = b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";
    let written = harness.net.tcp_write(&client.key(), response, harness.now);
    assert_eq!(written, response.len());

    let out = harness.net.egress();
    let segments = harness.tcp_segments(&out);
    let payload: Vec<u8> = segments
        .iter()
        .flat_map(|segment| segment.payload.clone())
        .collect();
    assert_eq!(payload, response);
    for segment in &segments {
        assert_eq!(
            segment.src, client.remote,
            "responses leave as the destination"
        );
        assert_eq!(segment.dst, client.local);
    }
}

#[test]
fn client_fin_half_closes_the_read_side_only() {
    let mut harness = Harness::default();
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 43_000),
        endpoint_v4([9, 9, 9, 9], 443),
    );
    client.connect(&mut harness);
    harness.feed(client.data(b"ping"));
    harness.feed(client.fin());

    let key = client.key();
    let flow = harness
        .net
        .tcp_flow(&key)
        .expect("still tracked after the FIN");
    assert!(!flow.may_recv(), "the read half sees EOF");
    assert!(flow.may_send(), "the write half stays open");
    assert_eq!(flow.state(), tcp::State::CloseWait);

    let written = harness.net.tcp_write(&key, b"pong", harness.now);
    assert_eq!(
        written, 4,
        "a response can still be written after the client's FIN"
    );
    let out = harness.net.egress();
    let payload: Vec<u8> = harness
        .tcp_segments(&out)
        .iter()
        .flat_map(|segment| segment.payload.clone())
        .collect();
    assert_eq!(payload, b"pong");
}

#[test]
fn closed_flows_are_released() {
    let mut harness = Harness::default();
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 43_500),
        endpoint_v4([9, 9, 9, 9], 25),
    );
    client.connect(&mut harness);
    let key = client.key();

    // The client's FIN moves the flow to CloseWait; the relay's close sends its own FIN, and the
    // client's ACK of that FIN walks the socket to Closed, where the flow is released.
    harness.feed(client.fin());
    assert_eq!(
        harness.net.tcp_flow(&key).unwrap().state(),
        tcp::State::CloseWait
    );

    harness.net.tcp_close(&key, harness.now);
    let out = harness.net.egress();
    let fin = harness
        .tcp_segments(&out)
        .into_iter()
        .find(|segment| segment.is_fin())
        .expect("the relay's close sends a FIN");
    client.ack = fin.seq_number + 1;
    harness.feed(client.ack());

    let flow = harness
        .net
        .tcp_flow(&key)
        .expect("kept until the relay removes it");
    assert!(
        flow.is_closed(),
        "the socket reached Closed, got {:?}",
        flow.state()
    );
    assert_eq!(harness.net.stats().tcp_closed, 1);

    harness.net.tcp_remove(&key);
    assert!(harness.net.tcp_flow(&key).is_none());
    assert_eq!(harness.net.tcp_flow_count(), 0);
}

#[test]
fn write_is_short_when_the_send_buffer_is_full() {
    let limits = Limits {
        tcp_tx_bytes: 4096,
        ..Limits::default()
    };
    let mut harness = Harness::new(limits);
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 44_000),
        endpoint_v4([203, 0, 113, 5], 443),
    );
    client.connect(&mut harness);

    let payload = vec![0x5au8; 16 * 1024];
    let written = harness.net.tcp_write(&client.key(), &payload, harness.now);
    assert!(
        written < payload.len(),
        "backpressure must surface as a short write, not as unbounded buffering"
    );
    assert!(written > 0);
}

#[test]
fn flow_table_cap_rejects_extra_syns() {
    let limits = Limits {
        max_tcp_flows: 1,
        ..Limits::default()
    };
    let mut harness = Harness::new(limits);
    let mut first = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 45_000),
        endpoint_v4([1, 1, 1, 1], 443),
    );
    let mut second = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 45_001),
        endpoint_v4([8, 8, 4, 4], 443),
    );

    first.connect(&mut harness);
    let out = harness.feed(second.syn());
    let segments = harness.tcp_segments(&out);
    assert_eq!(segments.len(), 1, "the over-cap SYN gets one segment back");
    assert_eq!(
        segments[0].control,
        TcpControl::Rst,
        "no socket is allocated, so smoltcp answers with the interface's RST"
    );
    assert_eq!(harness.net.tcp_flow_count(), 1);
    assert_eq!(harness.net.stats().tcp_rejected, 1);
}

#[test]
fn idle_flows_expire() {
    let limits = Limits {
        tcp_idle: smoltcp::time::Duration::from_secs(30),
        ..Limits::default()
    };
    let mut harness = Harness::new(limits);
    let mut client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 46_000),
        endpoint_v4([1, 0, 0, 1], 443),
    );
    client.connect(&mut harness);
    assert_eq!(harness.net.tcp_flow_count(), 1);

    harness.advance(29_000);
    harness.net.expire_idle(harness.now);
    assert_eq!(harness.net.tcp_flow_count(), 1, "not idle long enough");

    harness.advance(2_000);
    harness.net.expire_idle(harness.now);
    assert_eq!(harness.net.tcp_flow_count(), 0);
    assert_eq!(harness.net.stats().tcp_expired, 1);
}

#[test]
fn non_syn_control_packets_never_create_flows() {
    let mut harness = Harness::default();
    let client = TcpClient::new(
        endpoint_v4([10, 0, 0, 2], 47_000),
        endpoint_v4([1, 1, 1, 1], 22),
    );

    // A bare FIN / RST from a client that never opened a connection: unanswered, uncounted.
    let fin = smoltcp::wire::TcpControl::Fin;
    let packet = diting_netstack_spike::wire::emit_tcp(
        client.local,
        client.remote,
        client.seq,
        None,
        fin,
        &[],
    );
    harness.feed(packet);

    let rst = diting_netstack_spike::wire::emit_tcp(
        client.local,
        client.remote,
        client.seq,
        None,
        TcpControl::Rst,
        &[],
    );
    harness.feed(rst);

    assert_eq!(harness.net.tcp_flow_count(), 0);
    assert_eq!(harness.net.stats().tcp_accepted, 0);
}

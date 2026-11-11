//! The UDP half of the spike: the DNS server path (`engine_standalone.go`, `dns_packet.go`).
//!
//! UDP is the easier half but it has the same trap as TCP: the destination address is not known in
//! advance. `bind()` to a port with no address accepts every destination, and
//! `UdpMetadata::local_address` reports the address the datagram was actually sent to, so one
//! socket can serve every upstream address a client queries. These tests pin that behaviour, since
//! the DNS reply must leave from the upstream's address or the client's resolver rejects it.

mod support;

use diting_netstack_spike::wire;
use diting_netstack_spike::{Limits, UdpDatagram};
use support::{endpoint_v4, endpoint_v6, Harness};

fn query(id: u8) -> Vec<u8> {
    // A DNS-shaped payload: the spike does not parse it, it only has to survive verbatim.
    let mut payload = vec![0u8, id, 0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0];
    payload.extend_from_slice(b"\x07example\x04test\x00\x00\x01\x00\x01");
    payload
}

#[test]
fn binds_any_destination_on_the_first_datagram() {
    let mut harness = Harness::default();
    let client = endpoint_v4([10, 0, 0, 2], 55_555);
    let upstream = endpoint_v4([8, 8, 8, 8], 53);

    let payload = query(0x12);
    let out = harness.feed(wire::emit_udp(client, upstream, &payload));
    assert!(
        out.is_empty(),
        "an unbound client packet produces no reply of its own"
    );

    let datagram = harness
        .net
        .udp_take()
        .expect("the datagram reached the engine");
    assert_eq!(
        datagram.local, upstream,
        "the original destination is recovered"
    );
    assert_eq!(datagram.peer, client);
    assert_eq!(datagram.payload, payload);
    assert_eq!(harness.net.udp_binding_count(), 1);

    let answer = query(0x12);
    harness
        .net
        .udp_send(datagram.local, datagram.peer, &answer, harness.now)
        .expect("the reply is queued");
    let out = harness.net.egress();
    let datagrams = harness.udp_datagrams(&out);
    assert_eq!(datagrams.len(), 1);
    assert_eq!(
        datagrams[0].src, upstream,
        "the answer leaves from the upstream"
    );
    assert_eq!(datagrams[0].dst, client);
    assert_eq!(datagrams[0].payload, answer);
}

#[test]
fn one_binding_serves_every_upstream_address() {
    let mut harness = Harness::default();
    let client = endpoint_v4([10, 0, 0, 2], 55_556);
    let first = endpoint_v4([8, 8, 8, 8], 53);
    let second = endpoint_v4([1, 1, 1, 1], 53);

    harness.feed(wire::emit_udp(client, first, &query(1)));
    harness.feed(wire::emit_udp(client, second, &query(2)));
    assert_eq!(
        harness.net.udp_binding_count(),
        1,
        "every upstream on port 53 shares one socket"
    );

    let first_datagram = harness.net.udp_take().expect("first datagram");
    let second_datagram = harness.net.udp_take().expect("second datagram");
    assert_eq!(first_datagram.local, first);
    assert_eq!(second_datagram.local, second);

    harness
        .net
        .udp_send(
            second_datagram.local,
            second_datagram.peer,
            b"b",
            harness.now,
        )
        .unwrap();
    harness
        .net
        .udp_send(first_datagram.local, first_datagram.peer, b"a", harness.now)
        .unwrap();

    let out = harness.net.egress();
    let datagrams: Vec<UdpDatagram> = harness
        .udp_datagrams(&out)
        .into_iter()
        .map(|parsed| UdpDatagram {
            local: parsed.src,
            peer: parsed.dst,
            payload: parsed.payload,
        })
        .collect();
    assert_eq!(datagrams.len(), 2);
    assert!(datagrams
        .iter()
        .any(|d| d.local == first && d.payload == b"a"));
    assert!(datagrams
        .iter()
        .any(|d| d.local == second && d.payload == b"b"));
}

#[test]
fn replies_go_back_to_the_right_client() {
    let mut harness = Harness::default();
    let upstream = endpoint_v4([9, 9, 9, 9], 53);
    let first_client = endpoint_v4([10, 0, 0, 2], 60_001);
    let second_client = endpoint_v4([10, 0, 0, 3], 60_002);

    harness.feed(wire::emit_udp(first_client, upstream, &query(7)));
    harness.feed(wire::emit_udp(second_client, upstream, &query(8)));

    let first_datagram = harness.net.udp_take().unwrap();
    let second_datagram = harness.net.udp_take().unwrap();
    assert_eq!(first_datagram.peer, first_client);
    assert_eq!(second_datagram.peer, second_client);

    harness
        .net
        .udp_send(upstream, first_datagram.peer, &query(7), harness.now)
        .unwrap();
    harness
        .net
        .udp_send(upstream, second_datagram.peer, &query(8), harness.now)
        .unwrap();

    let out = harness.net.egress();
    let datagrams = harness.udp_datagrams(&out);
    assert_eq!(datagrams.len(), 2);
    assert_eq!(datagrams[0].dst, first_client);
    assert_eq!(datagrams[1].dst, second_client);
    assert_eq!(harness.net.stats().udp_datagrams_in, 2);
    assert_eq!(harness.net.stats().udp_datagrams_out, 2);
}

#[test]
fn carries_ipv6_dns() {
    let mut harness = Harness::default();
    let client = endpoint_v6([0xfd, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2], 60_003);
    let upstream = endpoint_v6(
        [
            0x26, 0x20, 0x47, 0, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x88, 0x88,
        ],
        53,
    );

    harness.feed(wire::emit_udp(client, upstream, &query(9)));
    let datagram = harness.net.udp_take().expect("IPv6 datagram surfaced");
    assert_eq!(datagram.local, upstream);
    assert_eq!(datagram.peer, client);

    harness
        .net
        .udp_send(datagram.local, datagram.peer, &query(9), harness.now)
        .unwrap();
    let out = harness.net.egress();
    let datagrams = harness.udp_datagrams(&out);
    assert_eq!(datagrams.len(), 1);
    assert_eq!(datagrams[0].src, upstream);
    assert_eq!(datagrams[0].dst, client);
}

#[test]
fn binding_cap_rejects_extra_ports() {
    let limits = Limits {
        max_udp_bindings: 1,
        ..Limits::default()
    };
    let mut harness = Harness::new(limits);
    let client = endpoint_v4([10, 0, 0, 2], 60_004);

    harness.feed(wire::emit_udp(
        client,
        endpoint_v4([8, 8, 8, 8], 53),
        &query(1),
    ));
    harness.net.udp_take().expect("port 53 is bound");
    harness.feed(wire::emit_udp(
        client,
        endpoint_v4([8, 8, 8, 8], 123),
        &query(2),
    ));

    assert!(
        harness.net.udp_take().is_none(),
        "the over-cap bind is dropped"
    );
    assert_eq!(harness.net.udp_binding_count(), 1);
    assert_eq!(harness.net.stats().udp_rejected, 1);
}

#[test]
fn reply_to_an_unbound_port_is_an_error() {
    let mut harness = Harness::default();
    let client = endpoint_v4([10, 0, 0, 2], 60_005);
    let result = harness
        .net
        .udp_send(endpoint_v4([8, 8, 8, 8], 53), client, b"x", harness.now);
    assert!(result.is_err(), "no socket, no reply");
}

#[test]
fn malformed_packets_are_counted_not_fatal() {
    let mut harness = Harness::default();
    harness.feed(vec![0u8; 8]);
    harness.feed(vec![0x45, 0, 0, 20, 0, 0, 0, 0, 64, 17]);
    assert!(harness.net.stats().malformed >= 1);
    assert_eq!(harness.net.tcp_flow_count(), 0);
    assert_eq!(harness.net.udp_binding_count(), 0);
}

//! The TUN corpus: the packet shapes stage 3 has to accept, frozen as a libpcap file.
//!
//! `rust/diting-netstack-spike` proved *that* the transparent proxy works; this corpus freezes *what
//! it has to work on*. The file is LINKTYPE_RAW (bare IP packets, exactly what a TUN device hands
//! `read(2)`), so it can be opened in Wireshark next to the engine's own dumps and replayed here.
//!
//! The pcap holds the client-to-upstream packets only — the ones the engine reads from the device:
//!
//! | # | packet | why stage 3 must handle it |
//! | --- | --- | --- |
//! | 1 | IPv4 TCP SYN `10.0.0.2:40000 → 93.184.216.34:443` | ordinary intercepted TLS flow |
//! | 2 | IPv6 TCP SYN `[2001:db8::2]:40001 → [2606:2800:220:1::1]:443` | IPv6-only networks |
//! | 3 | IPv4 UDP DNS `10.0.0.2:50000 → 8.8.8.8:53` | the resolver plain path |
//! | 4 | IPv6 UDP DNS `[2001:db8::2]:50002 → [2001:4860:4860::8888]:53` | IPv6 resolver path |
//! | 5 | IPv4 UDP 443 with a QUIC-shaped payload | the QUIC drop policy (`setUseTcpStack`) |
//! | 6 | IPv4 TCP 853 SYN `→ 1.1.1.1:853` | the encrypted-DNS block policy |
//!
//! The acknowledgement/data/FIN packets are **not** in the file: the stack picks the server's initial
//! sequence number at random, and a pcap containing it would change on every regeneration. The replay
//! drives the handshake forward with the observed SYN-ACK instead, which is also how the netstack
//! spike's own tests work.

use smoltcp::time::Instant;
use smoltcp::wire::{IpAddress, IpEndpoint, TcpControl};

use diting_netstack_spike::wire::{emit_tcp, emit_udp, endpoint_v4, endpoint_v6, parse_tcp};
use diting_netstack_spike::{Limits, Netstack};

/// libpcap `LINKTYPE_RAW`: the payload of every record is one bare IP packet.
pub const LINKTYPE_RAW: u32 = 101;
/// A fixed capture timestamp base (2023-11-14T22:13:20Z), so the file is byte-stable.
pub const BASE_SECONDS: u32 = 1_700_000_000;

/// One corpus packet.
pub struct Packet {
    pub label: &'static str,
    pub bytes: Vec<u8>,
}

fn dns_query() -> Vec<u8> {
    crate::dns::query("dns.example.test", 1)
}

/// The fennec-shaped QUIC payload: a long-header first byte plus filler, enough for the QUIC rule.
fn quic_payload() -> Vec<u8> {
    let mut payload = vec![0xc3u8];
    payload.resize(64, 0);
    payload
}

/// The client-to-upstream packets, in capture order.
pub fn packets() -> Vec<Packet> {
    let client_v4 = endpoint_v4([10, 0, 0, 2], 40_000);
    let client_v4_dns = endpoint_v4([10, 0, 0, 2], 50_000);
    let client_v4_quic = endpoint_v4([10, 0, 0, 2], 50_001);
    let client_v4_dot = endpoint_v4([10, 0, 0, 2], 50_003);
    let client_v6 = endpoint_v6(ipv6([0x2001, 0x0db8, 0, 0, 0, 0, 0, 2]), 40_001);
    let client_v6_dns = endpoint_v6(ipv6([0x2001, 0x0db8, 0, 0, 0, 0, 0, 2]), 50_002);

    vec![
        Packet {
            label: "ipv4-tcp-syn-443",
            bytes: emit_tcp(
                client_v4,
                endpoint_v4([93, 184, 216, 34], 443),
                1_000,
                None,
                TcpControl::Syn,
                &[],
            ),
        },
        Packet {
            label: "ipv6-tcp-syn-443",
            bytes: emit_tcp(
                client_v6,
                endpoint_v6(ipv6([0x2606, 0x2800, 0x0220, 0x0001, 0, 0, 0, 1]), 443),
                2_000,
                None,
                TcpControl::Syn,
                &[],
            ),
        },
        Packet {
            label: "ipv4-udp-dns-53",
            bytes: emit_udp(client_v4_dns, endpoint_v4([8, 8, 8, 8], 53), &dns_query()),
        },
        Packet {
            label: "ipv6-udp-dns-53",
            bytes: emit_udp(
                client_v6_dns,
                endpoint_v6(ipv6([0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888]), 53),
                &dns_query(),
            ),
        },
        Packet {
            label: "ipv4-udp-quic-443",
            bytes: emit_udp(
                client_v4_quic,
                endpoint_v4([142, 250, 66, 78], 443),
                &quic_payload(),
            ),
        },
        Packet {
            label: "ipv4-tcp-syn-853",
            bytes: emit_tcp(
                client_v4_dot,
                endpoint_v4([1, 1, 1, 1], 853),
                3_000,
                None,
                TcpControl::Syn,
                &[],
            ),
        },
    ]
}

/// Eight 16-bit groups as the 16 octets an IPv6 address is written with.
fn ipv6(groups: [u16; 8]) -> [u8; 16] {
    let mut octets = [0u8; 16];
    for (index, group) in groups.into_iter().enumerate() {
        octets[index * 2..index * 2 + 2].copy_from_slice(&group.to_be_bytes());
    }
    octets
}

/// Serializes the corpus as a libpcap file.
pub fn pcap() -> Vec<u8> {
    let mut file = Vec::new();
    // Global header: magic, 2.4, no timezone, no sigfigs, 65535 snap length, LINKTYPE_RAW.
    file.extend_from_slice(&0xa1b2_c3d4u32.to_be_bytes());
    file.extend_from_slice(&2u16.to_be_bytes());
    file.extend_from_slice(&4u16.to_be_bytes());
    file.extend_from_slice(&0u32.to_be_bytes());
    file.extend_from_slice(&0u32.to_be_bytes());
    file.extend_from_slice(&65_535u32.to_be_bytes());
    file.extend_from_slice(&LINKTYPE_RAW.to_be_bytes());
    for (index, packet) in packets().iter().enumerate() {
        // One record per millisecond, so a viewer shows them in order and the file stays stable.
        file.extend_from_slice(&BASE_SECONDS.to_be_bytes());
        file.extend_from_slice(&(index as u32 * 1_000).to_be_bytes());
        file.extend_from_slice(&(packet.bytes.len() as u32).to_be_bytes());
        file.extend_from_slice(&(packet.bytes.len() as u32).to_be_bytes());
        file.extend_from_slice(&packet.bytes);
    }
    file
}

/// Splits a libpcap file into its IP packets, rejecting anything the engine could not have written.
pub fn parse_pcap(bytes: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    if bytes.len() < 24 {
        return Err("the capture header is truncated".to_string());
    }
    let magic = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
    if magic != 0xa1b2_c3d4 {
        return Err(format!("unexpected pcap magic {magic:#x}"));
    }
    let network = u32::from_be_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]);
    if network != LINKTYPE_RAW {
        return Err(format!(
            "the capture is link type {network}, not LINKTYPE_RAW"
        ));
    }
    let mut packets = Vec::new();
    let mut offset = 24;
    while offset + 16 <= bytes.len() {
        let length = u32::from_be_bytes([
            bytes[offset + 8],
            bytes[offset + 9],
            bytes[offset + 10],
            bytes[offset + 11],
        ]) as usize;
        offset += 16;
        let end = offset
            .checked_add(length)
            .ok_or_else(|| "the record length overflows".to_string())?;
        if end > bytes.len() {
            return Err("a record is truncated".to_string());
        }
        packets.push(bytes[offset..end].to_vec());
        offset = end;
    }
    Ok(packets)
}

/// The single SYN handshake the replay completes, so the data path is exercised too.
const REPLAY_PAYLOAD: &[u8] = b"GET /corpus HTTP/1.1\r\nHost: example.test\r\n\r\n";

/// Replays the capture through the transparent proxy.
pub fn replay(bytes: &[u8]) -> Result<usize, String> {
    let captured = parse_pcap(bytes)?;
    let expected = packets();
    if captured.len() != expected.len() {
        return Err(format!(
            "the capture has {} packets, the corpus defines {}",
            captured.len(),
            expected.len()
        ));
    }
    for (index, packet) in captured.iter().enumerate() {
        if *packet != expected[index].bytes {
            return Err(format!(
                "packet {index} ({}) changed: {}",
                expected[index].label,
                crate::hex(packet)
            ));
        }
        // Every record must be one bare IP packet with a valid shape.
        if diting_netstack_spike::wire::split_ip(packet).is_none() {
            return Err(format!("packet {index} is not an IP packet"));
        }
    }

    // A fixed smoltcp clock: the corpus must not depend on the wall clock.
    let now = Instant::from_millis(1_000);
    let mut net = Netstack::new(Limits::default());
    for packet in &captured {
        net.ingress(packet, now);
        net.poll(now);
    }

    // Three TCP flows, one per SYN (IPv4:443, IPv6:443, IPv4:853), and two UDP destination ports.
    if net.tcp_flow_count() != 3 {
        return Err(format!(
            "expected 3 TCP flows, got {}",
            net.tcp_flow_count()
        ));
    }
    if net.udp_binding_count() != 2 {
        return Err(format!(
            "expected UDP bindings for ports 53 and 443, got {}",
            net.udp_binding_count()
        ));
    }

    // Every datagram still carries its original destination, which is what "answer as the upstream"
    // depends on.
    let mut datagrams = Vec::new();
    while let Some(datagram) = net.udp_take() {
        datagrams.push(datagram);
    }
    if datagrams.len() != 3 {
        return Err(format!("expected 3 datagrams, got {}", datagrams.len()));
    }
    let payloads: Vec<(u16, usize)> = datagrams
        .iter()
        .map(|datagram| (datagram.local.port, datagram.payload.len()))
        .collect();
    let dns_len = dns_query().len();
    let quic_len = quic_payload().len();
    let expected_payloads = [(53u16, dns_len), (53, dns_len), (443, quic_len)];
    if payloads != expected_payloads {
        return Err(format!(
            "the datagrams changed: {payloads:?} (expected {expected_payloads:?})"
        ));
    }
    // The IPv6 DNS datagram is addressed to the IPv6 upstream: the local address is preserved.
    let ipv6_dns = datagrams
        .iter()
        .find(|datagram| {
            datagram.local.port == 53 && matches!(datagram.peer.addr, IpAddress::Ipv6(_))
        })
        .ok_or_else(|| "the IPv6 DNS datagram is missing".to_string())?;
    if ipv6_dns.payload != dns_query() {
        return Err("the IPv6 DNS payload changed".to_string());
    }

    // Complete the IPv4 handshake against the stack's own SYN-ACK, then relay one request.
    let client = endpoint_v4([10, 0, 0, 2], 40_000);
    let server = endpoint_v4([93, 184, 216, 34], 443);
    let syn_ack = net
        .egress()
        .into_iter()
        .filter_map(|packet| parse_tcp(&packet))
        .find(|segment| segment.is_syn_ack() && segment.src == server && segment.dst == client)
        .ok_or_else(|| "the stack did not answer the SYN".to_string())?;
    let key = diting_netstack_spike::TcpKey::new(server, client);

    let ack = emit_tcp(
        client,
        server,
        syn_ack
            .ack_number
            .expect("a SYN-ACK acknowledges the client"),
        Some(syn_ack.seq_number + 1),
        TcpControl::None,
        &[],
    );
    net.ingress(&ack, now);
    net.poll(now);

    let data = emit_tcp(
        client,
        server,
        syn_ack
            .ack_number
            .expect("a SYN-ACK acknowledges the client"),
        Some(syn_ack.seq_number + 1),
        TcpControl::None,
        REPLAY_PAYLOAD,
    );
    net.ingress(&data, now);
    net.poll(now);

    let mut received = vec![0u8; REPLAY_PAYLOAD.len() + 8];
    let read = net.tcp_read(&key, &mut received);
    if read != REPLAY_PAYLOAD.len() || &received[..read] != REPLAY_PAYLOAD {
        return Err(format!(
            "the relayed payload changed: {}",
            crate::hex(&received[..read])
        ));
    }
    Ok(captured.len())
}

/// The endpoint the replay relays on, exposed so the test can assert on it.
pub fn replay_flow() -> (IpEndpoint, IpEndpoint) {
    (
        endpoint_v4([93, 184, 216, 34], 443),
        endpoint_v4([10, 0, 0, 2], 40_000),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_capture_round_trips() {
        let file = pcap();
        let captured = parse_pcap(&file).expect("the capture parses");
        let expected: Vec<Vec<u8>> = packets().into_iter().map(|packet| packet.bytes).collect();
        assert_eq!(captured, expected);
    }

    #[test]
    fn a_non_raw_capture_is_rejected() {
        let mut file = pcap();
        file[20..24].copy_from_slice(&1u32.to_be_bytes()); // LINKTYPE_ETHERNET
        assert!(parse_pcap(&file).is_err());
    }

    #[test]
    fn a_truncated_record_is_rejected() {
        let mut file = pcap();
        file.truncate(file.len() - 4);
        assert!(parse_pcap(&file).is_err());
    }

    #[test]
    fn the_shapes_are_stable() {
        let corpus = packets();
        assert_eq!(corpus.len(), 6);
        // `split_ip` only carries addresses; the ports come from the L4 parser.
        let first = parse_tcp(&corpus[0].bytes).expect("a TCP segment");
        assert_eq!(first.src.port, 40_000);
        assert_eq!(first.dst.port, 443);
        assert!(!first.is_syn_ack() && first.control == TcpControl::Syn);
        let dot = parse_tcp(&corpus[5].bytes).expect("a TCP segment");
        assert_eq!(dot.dst.port, 853);
        let dns = diting_netstack_spike::wire::parse_udp(&corpus[2].bytes).expect("a UDP datagram");
        assert_eq!(dns.dst.port, 53);
    }
}

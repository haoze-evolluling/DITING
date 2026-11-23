use smoltcp::time::Instant;
use smoltcp::wire::{IpAddress, TcpControl};

use diting_netstack_spike::wire::{emit_tcp, emit_udp, endpoint_v4, endpoint_v6, parse_tcp};
use diting_netstack_spike::{Limits, Netstack};

pub const LINKTYPE_RAW: u32 = 101;
pub const BASE_SECONDS: u32 = 1_700_000_000;

pub struct Packet {
    pub label: &'static str,
    pub bytes: Vec<u8>,
}

fn dns_query() -> Vec<u8> {
    crate::dns::query("dns.example.test", 1)
}

fn quic_payload() -> Vec<u8> {
    let mut payload = vec![0xc3u8];
    payload.resize(64, 0);
    payload
}

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

fn ipv6(groups: [u16; 8]) -> [u8; 16] {
    let mut octets = [0u8; 16];
    for (index, group) in groups.into_iter().enumerate() {
        octets[index * 2..index * 2 + 2].copy_from_slice(&group.to_be_bytes());
    }
    octets
}

pub fn pcap() -> Vec<u8> {
    let mut file = Vec::new();
    file.extend_from_slice(&0xa1b2_c3d4u32.to_be_bytes());
    file.extend_from_slice(&2u16.to_be_bytes());
    file.extend_from_slice(&4u16.to_be_bytes());
    file.extend_from_slice(&0u32.to_be_bytes());
    file.extend_from_slice(&0u32.to_be_bytes());
    file.extend_from_slice(&65_535u32.to_be_bytes());
    file.extend_from_slice(&LINKTYPE_RAW.to_be_bytes());
    for (index, packet) in packets().iter().enumerate() {
        file.extend_from_slice(&BASE_SECONDS.to_be_bytes());
        file.extend_from_slice(&(index as u32 * 1_000).to_be_bytes());
        file.extend_from_slice(&(packet.bytes.len() as u32).to_be_bytes());
        file.extend_from_slice(&(packet.bytes.len() as u32).to_be_bytes());
        file.extend_from_slice(&packet.bytes);
    }
    file
}

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

const REPLAY_PAYLOAD: &[u8] = b"GET /corpus HTTP/1.1\r\nHost: example.test\r\n\r\n";

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
        if diting_netstack_spike::wire::split_ip(packet).is_none() {
            return Err(format!("packet {index} is not an IP packet"));
        }
    }

    let now = Instant::from_millis(1_000);
    let mut net = Netstack::new(Limits::default());
    for packet in &captured {
        net.ingress(packet, now);
        net.poll(now);
    }

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
    let ipv6_dns = datagrams
        .iter()
        .find(|datagram| {
            datagram.local.port == 53 && matches!(datagram.peer.addr, IpAddress::Ipv6(_))
        })
        .ok_or_else(|| "the IPv6 DNS datagram is missing".to_string())?;
    if ipv6_dns.payload != dns_query() {
        return Err("the IPv6 DNS payload changed".to_string());
    }

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
        file[20..24].copy_from_slice(&1u32.to_be_bytes());
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

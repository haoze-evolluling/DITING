//! The client side of the spike: a hand-written TCP/UDP peer and the harness around the stack.
//!
//! Nothing here needs a device, a port or a privilege. `Harness` advances a fake clock and shuttles
//! packets between the test's crafted bytes and `Netstack`, which is exactly the boundary the
//! engine's TUN adapter will sit on.

#![allow(dead_code)]

use diting_netstack_spike::wire;
use diting_netstack_spike::{Limits, Netstack, TcpKey};
use smoltcp::time::{Duration, Instant};
use smoltcp::wire::{IpEndpoint, TcpControl};

pub use diting_netstack_spike::wire::{endpoint_v4, endpoint_v6};

pub struct Harness {
    pub net: Netstack,
    pub now: Instant,
}

impl Default for Harness {
    fn default() -> Self {
        Self::new(Limits::default())
    }
}

impl Harness {
    pub fn new(limits: Limits) -> Self {
        Self {
            net: Netstack::new(limits),
            now: Instant::ZERO,
        }
    }

    pub fn advance(&mut self, millis: u64) {
        self.now += Duration::from_millis(millis);
    }

    /// Deliver one client packet and return everything the stack wrote back.
    pub fn feed(&mut self, packet: Vec<u8>) -> Vec<Vec<u8>> {
        self.net.ingress(&packet, self.now);
        self.net.egress()
    }

    /// A timer tick: no new client packet, just another `poll`.
    pub fn tick(&mut self) -> Vec<Vec<u8>> {
        self.net.poll(self.now);
        self.net.egress()
    }

    pub fn tcp_segments(&self, packets: &[Vec<u8>]) -> Vec<wire::TcpSegment> {
        packets
            .iter()
            .filter_map(|packet| wire::parse_tcp(packet))
            .collect()
    }

    pub fn udp_datagrams(&self, packets: &[Vec<u8>]) -> Vec<wire::UdpSegment> {
        packets
            .iter()
            .filter_map(|packet| wire::parse_udp(packet))
            .collect()
    }
}

/// A TCP client with just enough sequencing to hold a conversation: SYN, ACK, data, FIN.
pub struct TcpClient {
    pub local: IpEndpoint,
    pub remote: IpEndpoint,
    pub seq: u32,
    pub ack: u32,
}

impl TcpClient {
    pub fn new(local: IpEndpoint, remote: IpEndpoint) -> Self {
        Self {
            local,
            remote,
            seq: 1_000,
            ack: 0,
        }
    }

    pub fn key(&self) -> TcpKey {
        TcpKey::new(self.remote, self.local)
    }

    pub fn syn(&mut self) -> Vec<u8> {
        let packet = wire::emit_tcp(
            self.local,
            self.remote,
            self.seq,
            None,
            TcpControl::Syn,
            &[],
        );
        self.seq += 1;
        packet
    }

    /// Adopt the server's initial sequence number and keep our own next sequence.
    pub fn accept_syn_ack(&mut self, syn_ack: &wire::TcpSegment) {
        assert!(syn_ack.is_syn_ack(), "expected a SYN-ACK, got {syn_ack:?}");
        assert_eq!(syn_ack.dst, self.local, "SYN-ACK addressed to the client");
        assert_eq!(
            syn_ack.src, self.remote,
            "SYN-ACK sourced from the destination"
        );
        self.ack = syn_ack.seq_number + 1;
    }

    pub fn ack(&mut self) -> Vec<u8> {
        wire::emit_tcp(
            self.local,
            self.remote,
            self.seq,
            Some(self.ack),
            TcpControl::None,
            &[],
        )
    }

    pub fn data(&mut self, payload: &[u8]) -> Vec<u8> {
        let packet = wire::emit_tcp(
            self.local,
            self.remote,
            self.seq,
            Some(self.ack),
            TcpControl::Psh,
            payload,
        );
        self.seq += payload.len() as u32;
        packet
    }

    pub fn fin(&mut self) -> Vec<u8> {
        let packet = wire::emit_tcp(
            self.local,
            self.remote,
            self.seq,
            Some(self.ack),
            TcpControl::Fin,
            &[],
        );
        self.seq += 1;
        packet
    }

    /// SYN, then the handshake completes. Returns the SYN-ACK for the caller's assertions.
    pub fn connect(&mut self, harness: &mut Harness) -> wire::TcpSegment {
        let out = harness.feed(self.syn());
        let segments = harness.tcp_segments(&out);
        assert_eq!(segments.len(), 1, "one SYN-ACK expected, got {segments:?}");
        let syn_ack = segments[0].clone();
        self.accept_syn_ack(&syn_ack);
        let out = harness.feed(self.ack());
        assert!(
            harness.tcp_segments(&out).is_empty(),
            "the handshake's third packet produces no reply"
        );
        syn_ack
    }
}

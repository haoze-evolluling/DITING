use std::time::{Duration, Instant};

use diting_engine::tunnel::MemoryLink;
use smoltcp::wire::{IpEndpoint, TcpControl};

use super::wire;

pub const WAIT: Duration = Duration::from_secs(5);

pub fn wait_for(
    link: &MemoryLink,
    timeout: Duration,
    predicate: impl Fn(&[u8]) -> bool,
) -> Option<Vec<u8>> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let packet = link.wait_outbound(Duration::from_millis(50))?;
        if predicate(&packet) {
            return Some(packet);
        }
    }
    None
}

pub fn wait_tcp(
    link: &MemoryLink,
    predicate: impl Fn(&wire::TcpSegment) -> bool,
) -> Option<wire::TcpSegment> {
    wait_for(link, WAIT, |packet| {
        wire::parse_tcp(packet)
            .map(|segment| predicate(&segment))
            .unwrap_or(false)
    })
    .and_then(|packet| wire::parse_tcp(&packet))
}

pub fn wait_udp(
    link: &MemoryLink,
    predicate: impl Fn(&wire::UdpSegment) -> bool,
) -> Option<wire::UdpSegment> {
    wait_for(link, WAIT, |packet| {
        wire::parse_udp(packet)
            .map(|segment| predicate(&segment))
            .unwrap_or(false)
    })
    .and_then(|packet| wire::parse_udp(&packet))
}

pub struct Client {
    pub local: IpEndpoint,
    pub remote: IpEndpoint,
    seq: u32,
    ack: u32,
}

impl Client {
    pub fn new(local: IpEndpoint, remote: IpEndpoint) -> Self {
        Self {
            local,
            remote,
            seq: 1_000,
            ack: 0,
        }
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

    pub fn connect(&mut self, link: &MemoryLink) {
        let expected = self.remote;
        let local = self.local;
        link.feed(self.syn());
        let syn_ack = wait_tcp(link, |segment| {
            segment.is_syn_ack() && segment.src == expected && segment.dst == local
        })
        .expect("a SYN-ACK sourced from the original destination");
        self.ack = syn_ack.seq_number + 1;
        link.feed(self.ack());
    }
}

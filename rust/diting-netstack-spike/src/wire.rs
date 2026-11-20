use smoltcp::phy::ChecksumCapabilities;
use smoltcp::wire::{
    IpAddress, IpEndpoint, IpProtocol, IpVersion, Ipv4Address, Ipv4Packet, Ipv4Repr, Ipv6Address,
    Ipv6Packet, Ipv6Repr, TcpControl, TcpPacket, TcpRepr, TcpSeqNumber, UdpPacket, UdpRepr,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TcpSegment {
    pub src: IpEndpoint,
    pub dst: IpEndpoint,
    pub seq_number: u32,
    pub ack_number: Option<u32>,
    pub control: TcpControl,
    pub payload: Vec<u8>,
}

impl TcpSegment {
    pub fn is_syn_ack(&self) -> bool {
        self.control == TcpControl::Syn && self.ack_number.is_some()
    }

    pub fn is_fin(&self) -> bool {
        self.control == TcpControl::Fin
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UdpSegment {
    pub src: IpEndpoint,
    pub dst: IpEndpoint,
    pub payload: Vec<u8>,
}

pub fn endpoint_v4(octets: [u8; 4], port: u16) -> IpEndpoint {
    IpEndpoint::new(IpAddress::Ipv4(Ipv4Address::from(octets)), port)
}

pub fn endpoint_v6(octets: [u8; 16], port: u16) -> IpEndpoint {
    IpEndpoint::new(IpAddress::Ipv6(Ipv6Address::from(octets)), port)
}

pub fn emit_tcp(
    src: IpEndpoint,
    dst: IpEndpoint,
    seq_number: u32,
    ack_number: Option<u32>,
    control: TcpControl,
    payload: &[u8],
) -> Vec<u8> {
    let repr = TcpRepr {
        src_port: src.port,
        dst_port: dst.port,
        control,
        seq_number: TcpSeqNumber(seq_number as i32),
        ack_number: ack_number.map(|ack| TcpSeqNumber(ack as i32)),
        window_len: 64240,
        window_scale: None,
        max_seg_size: None,
        sack_permitted: false,
        sack_ranges: [None, None, None],
        timestamp: None,
        payload,
    };

    let checksum = ChecksumCapabilities::default();
    let mut segment = vec![0u8; repr.buffer_len()];
    repr.emit(
        &mut TcpPacket::new_unchecked(&mut segment[..]),
        &src.addr,
        &dst.addr,
        &checksum,
    );
    emit_ip(src.addr, dst.addr, IpProtocol::Tcp, &segment)
}

pub fn emit_udp(src: IpEndpoint, dst: IpEndpoint, payload: &[u8]) -> Vec<u8> {
    let repr = UdpRepr {
        src_port: src.port,
        dst_port: dst.port,
    };

    let checksum = ChecksumCapabilities::default();
    let mut segment = vec![0u8; repr.header_len() + payload.len()];
    repr.emit(
        &mut UdpPacket::new_unchecked(&mut segment[..]),
        &src.addr,
        &dst.addr,
        payload.len(),
        |buf| buf.copy_from_slice(payload),
        &checksum,
    );
    emit_ip(src.addr, dst.addr, IpProtocol::Udp, &segment)
}

fn emit_ip(src: IpAddress, dst: IpAddress, protocol: IpProtocol, payload: &[u8]) -> Vec<u8> {
    let checksum = ChecksumCapabilities::default();
    match (src, dst) {
        (IpAddress::Ipv4(src_addr), IpAddress::Ipv4(dst_addr)) => {
            let repr = Ipv4Repr {
                src_addr,
                dst_addr,
                next_header: protocol,
                payload_len: payload.len(),
                hop_limit: 64,
            };
            let mut buffer = vec![0u8; repr.buffer_len() + payload.len()];
            let mut packet = Ipv4Packet::new_unchecked(&mut buffer[..]);
            repr.emit(&mut packet, &checksum);
            packet.payload_mut().copy_from_slice(payload);
            buffer
        }
        (IpAddress::Ipv6(src_addr), IpAddress::Ipv6(dst_addr)) => {
            let repr = Ipv6Repr {
                src_addr,
                dst_addr,
                next_header: protocol,
                payload_len: payload.len(),
                hop_limit: 64,
            };
            let mut buffer = vec![0u8; repr.buffer_len() + payload.len()];
            let mut packet = Ipv6Packet::new_unchecked(&mut buffer[..]);
            repr.emit(&mut packet);
            packet.payload_mut().copy_from_slice(payload);
            buffer
        }
        _ => panic!("address family mismatch: {src} -> {dst}"),
    }
}

pub fn split_ip(packet: &[u8]) -> Option<(IpEndpoint, IpEndpoint, IpProtocol, &[u8])> {
    match IpVersion::of_packet(packet).ok()? {
        IpVersion::Ipv4 => {
            let ipv4 = Ipv4Packet::new_checked(packet).ok()?;
            Some((
                IpEndpoint::new(IpAddress::Ipv4(ipv4.src_addr()), 0),
                IpEndpoint::new(IpAddress::Ipv4(ipv4.dst_addr()), 0),
                ipv4.next_header(),
                ipv4.payload(),
            ))
        }
        IpVersion::Ipv6 => {
            let ipv6 = Ipv6Packet::new_checked(packet).ok()?;
            Some((
                IpEndpoint::new(IpAddress::Ipv6(ipv6.src_addr()), 0),
                IpEndpoint::new(IpAddress::Ipv6(ipv6.dst_addr()), 0),
                ipv6.next_header(),
                ipv6.payload(),
            ))
        }
    }
}

pub fn parse_tcp(packet: &[u8]) -> Option<TcpSegment> {
    let (src_addr, dst_addr, protocol, payload) = split_ip(packet)?;
    if protocol != IpProtocol::Tcp {
        return None;
    }
    let packet = TcpPacket::new_checked(payload).ok()?;
    let repr = TcpRepr::parse(
        &packet,
        &src_addr.addr,
        &dst_addr.addr,
        &ChecksumCapabilities::default(),
    )
    .ok()?;
    Some(TcpSegment {
        src: IpEndpoint::new(src_addr.addr, repr.src_port),
        dst: IpEndpoint::new(dst_addr.addr, repr.dst_port),
        seq_number: repr.seq_number.0 as u32,
        ack_number: repr.ack_number.map(|ack| ack.0 as u32),
        control: repr.control,
        payload: repr.payload.to_vec(),
    })
}

pub fn parse_udp(packet: &[u8]) -> Option<UdpSegment> {
    let (src_addr, dst_addr, protocol, payload) = split_ip(packet)?;
    if protocol != IpProtocol::Udp {
        return None;
    }
    let packet = UdpPacket::new_checked(payload).ok()?;
    let repr = UdpRepr::parse(
        &packet,
        &src_addr.addr,
        &dst_addr.addr,
        &ChecksumCapabilities::default(),
    )
    .ok()?;
    Some(UdpSegment {
        src: IpEndpoint::new(src_addr.addr, repr.src_port),
        dst: IpEndpoint::new(dst_addr.addr, repr.dst_port),
        payload: packet.payload().to_vec(),
    })
}

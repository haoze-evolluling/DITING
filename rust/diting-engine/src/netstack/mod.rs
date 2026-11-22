pub mod device;
pub mod flow;
pub mod stack;

use std::sync::OnceLock;
use std::time::Instant as StdInstant;

pub use flow::{FlowOutput, Stats, TcpKey, UdpDatagram};
pub use stack::{Limits, Netstack, UdpSendError};

fn base() -> StdInstant {
    static BASE: OnceLock<StdInstant> = OnceLock::new();
    *BASE.get_or_init(StdInstant::now)
}

pub fn now() -> smoltcp::time::Instant {
    smoltcp::time::Instant::from_micros(base().elapsed().as_micros() as i64)
}

pub fn millis(value: u64) -> smoltcp::time::Duration {
    smoltcp::time::Duration::from_millis(value)
}

/// 把 IP 地址写成网络字节序，返回实际长度（4 或 16）。
///
/// 每个入站流都会调用一次，所以写成调用方提供的栈缓冲，避免一次堆分配。
pub fn address_bytes_into(address: smoltcp::wire::IpAddress, out: &mut [u8; 16]) -> usize {
    match address {
        smoltcp::wire::IpAddress::Ipv4(address) => {
            out[..4].copy_from_slice(&address.octets());
            4
        }
        smoltcp::wire::IpAddress::Ipv6(address) => {
            out[..16].copy_from_slice(&address.octets());
            16
        }
    }
}

pub fn socket_addr(endpoint: smoltcp::wire::IpEndpoint) -> std::net::SocketAddr {
    let address = match endpoint.addr {
        smoltcp::wire::IpAddress::Ipv4(address) => std::net::IpAddr::V4(address),
        smoltcp::wire::IpAddress::Ipv6(address) => std::net::IpAddr::V6(address),
    };
    std::net::SocketAddr::new(address, endpoint.port)
}

pub fn flow_addr(address: smoltcp::wire::IpAddress) -> diting_flow_core::FlowAddr {
    match address {
        smoltcp::wire::IpAddress::Ipv4(v4) => diting_flow_core::FlowAddr::V4(v4),
        smoltcp::wire::IpAddress::Ipv6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => diting_flow_core::FlowAddr::V4(v4),
            None => diting_flow_core::FlowAddr::V6(v6),
        },
    }
}

pub fn address_text(address: smoltcp::wire::IpAddress) -> String {
    let mut bytes = [0u8; 16];
    let len = address_bytes_into(address, &mut bytes);
    if len == 4 {
        diting_dns_wire::format_ipv4(&bytes[..4])
    } else {
        diting_dns_wire::format_ipv6(&bytes[..16])
    }
}

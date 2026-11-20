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

pub fn address_bytes(address: smoltcp::wire::IpAddress) -> Vec<u8> {
    match address {
        smoltcp::wire::IpAddress::Ipv4(address) => address.octets().to_vec(),
        smoltcp::wire::IpAddress::Ipv6(address) => address.octets().to_vec(),
    }
}

pub fn socket_addr(endpoint: smoltcp::wire::IpEndpoint) -> std::net::SocketAddr {
    let address = match endpoint.addr {
        smoltcp::wire::IpAddress::Ipv4(address) => std::net::IpAddr::V4(address),
        smoltcp::wire::IpAddress::Ipv6(address) => std::net::IpAddr::V6(address),
    };
    std::net::SocketAddr::new(address, endpoint.port)
}

pub fn address_text(address: smoltcp::wire::IpAddress) -> String {
    let bytes = address_bytes(address);
    if bytes.len() == 4 {
        diting_dns_wire::format_ipv4(&bytes)
    } else {
        diting_dns_wire::format_ipv6(&bytes)
    }
}

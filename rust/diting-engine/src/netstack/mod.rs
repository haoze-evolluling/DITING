//! The userspace TCP/IP stack behind the TUN device.
//!
//! This is stage 3's data plane. It replaces the gVisor stack the Go engine got from tun2socks:
//! [`stack::Netstack`] accepts packets for **any** destination address and port (transparent
//! proxying), [`device::IpDevice`] is the packet boundary the TUN adapter feeds, and
//! [`flow`] holds the flow records and counters.
//!
//! The Go engine's `tcp_ip_stack.go` / `tcp_stack_handlers.go` dispatch L4 flows to goroutines that
//! relay them; here the stack produces [`FlowOutput`] and [`UdpDatagram`] values that
//! [`crate::tunnel`] hands to the same kind of handlers (DNS first; direct and proxied relays are
//! stage 4).

pub mod device;
pub mod flow;
pub mod stack;

use std::sync::OnceLock;
use std::time::Instant as StdInstant;

pub use flow::{FlowOutput, Stats, TcpKey, UdpDatagram};
pub use stack::{Limits, Netstack, UdpSendError};

/// The monotonic base every `smoltcp` timestamp is measured from.
///
/// `smoltcp` wants microsecond `Instant`s; the engine wants a clock that never jumps when the wall
/// clock is adjusted (a phone with a changed timezone must not see every flow expire or every TCP
/// retransmission fire at once). One process-wide base, `StdInstant`'s monotonicity after it.
fn base() -> StdInstant {
    static BASE: OnceLock<StdInstant> = OnceLock::new();
    *BASE.get_or_init(StdInstant::now)
}

/// The current `smoltcp` timestamp.
pub fn now() -> smoltcp::time::Instant {
    smoltcp::time::Instant::from_micros(base().elapsed().as_micros() as i64)
}

/// A `smoltcp` duration from milliseconds, for the tests and the session's short sleeps.
pub fn millis(value: u64) -> smoltcp::time::Duration {
    smoltcp::time::Duration::from_millis(value)
}

/// The 4 or 16 bytes of an address, in `netip.Addr.AsSlice` shape (what the kernels take).
pub fn address_bytes(address: smoltcp::wire::IpAddress) -> Vec<u8> {
    match address {
        smoltcp::wire::IpAddress::Ipv4(address) => address.octets().to_vec(),
        smoltcp::wire::IpAddress::Ipv6(address) => address.octets().to_vec(),
    }
}

/// The `std::net::SocketAddr` form, for the outbound dials.
pub fn socket_addr(endpoint: smoltcp::wire::IpEndpoint) -> std::net::SocketAddr {
    let address = match endpoint.addr {
        smoltcp::wire::IpAddress::Ipv4(address) => std::net::IpAddr::V4(address),
        smoltcp::wire::IpAddress::Ipv6(address) => std::net::IpAddr::V6(address),
    };
    std::net::SocketAddr::new(address, endpoint.port)
}

/// `net.IP.String()` for an address: what the connection log and the UID callback carry.
pub fn address_text(address: smoltcp::wire::IpAddress) -> String {
    let bytes = address_bytes(address);
    if bytes.len() == 4 {
        diting_dns_wire::format_ipv4(&bytes)
    } else {
        diting_dns_wire::format_ipv6(&bytes)
    }
}

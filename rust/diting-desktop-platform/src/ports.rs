//! Listener address predicates and quick bind probes.
//!
//! Used before takeover: if 53 is already occupied by another resolver the service must refuse to
//! start rather than steal the socket. `SO_REUSEADDR` is deliberately *not* set — on Windows it
//! would let a second process bind the same UDP port and silently split DNS traffic.

use std::net::{SocketAddr, UdpSocket};

/// True when every address is a local loopback endpoint (no LAN exposure).
pub fn is_only_loopback(udp_addrs: &[String], tcp_addrs: &[String]) -> bool {
    udp_addrs
        .iter()
        .chain(tcp_addrs.iter())
        .all(|address| is_loopback_address(address))
}

pub fn is_loopback_address(address: &str) -> bool {
    let host = host_of(address).trim_matches(['[', ']']);
    host == "127.0.0.1" || host == "::1" || host == "localhost"
}

/// `AreAddressesAvailable`: all UDP and TCP addresses can be bound right now.
pub fn are_addresses_available(udp_addrs: &[String], tcp_addrs: &[String]) -> bool {
    udp_addrs.iter().all(|address| test_udp_bind(address))
        && tcp_addrs.iter().all(|address| test_tcp_bind(address))
}

pub fn test_udp_bind(address: &str) -> bool {
    let Ok(addr) = parse_socket_addr(address) else {
        return false;
    };
    match UdpSocket::bind(addr) {
        Ok(socket) => {
            drop(socket);
            true
        }
        Err(_) => false,
    }
}

pub fn test_tcp_bind(address: &str) -> bool {
    let Ok(addr) = parse_socket_addr(address) else {
        return false;
    };
    std::net::TcpListener::bind(addr).is_ok()
}

fn parse_socket_addr(address: &str) -> Result<SocketAddr, ()> {
    address.parse::<SocketAddr>().map_err(|_| ())
}

fn host_of(address: &str) -> &str {
    if let Some(rest) = address.strip_prefix('[') {
        if let Some((host, _)) = rest.split_once(']') {
            return host;
        }
    }
    match address.rsplit_once(':') {
        Some((host, port)) if port.chars().all(|ch| ch.is_ascii_digit()) => host,
        _ => address,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loopback_detection() {
        assert!(is_only_loopback(
            &["127.0.0.1:53".into()],
            &["[::1]:53".into()]
        ));
        assert!(!is_only_loopback(&["0.0.0.0:53".into()], &[]));
        assert!(is_loopback_address("localhost:53"));
        assert!(!is_loopback_address("192.168.1.1:53"));
    }

    #[test]
    fn binds_an_ephemeral_port() {
        let udp = UdpSocket::bind("127.0.0.1:0").unwrap();
        let port = udp.local_addr().unwrap().port();
        assert!(test_tcp_bind(&format!("127.0.0.1:{port}")));
    }
}

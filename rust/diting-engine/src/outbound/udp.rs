//! The datagram side of an outbound transport: a connected UDP socket, or SOCKS5 UDP ASSOCIATE.
//!
//! Go modelled both as `net.PacketConn`; here the connection is always to one destination (the TUN
//! flow's `5-tuple` fixes it), so a connected transport is enough and the relay loop stays simple.
//!
//! # SOCKS5 framing
//!
//! A proxied datagram is `RSV(0,0,0) | ATYP | address | port | payload`, and the reply the same
//! shape. [`diting_proxy_core::socks5::datagram`] builds the request and `parse_datagram` returns the
//! payload offset, so this module only owns the socket and the control connection.
//!
//! The control TCP connection from `UDP ASSOCIATE` must stay open for the lifetime of the
//! association (closing it ends the relay), which is why [`Socks5Udp`] keeps it.

use std::net::SocketAddr;

use diting_proxy_core::socks5;
use tokio::net::{TcpStream, UdpSocket};

use crate::outbound::handshake;
use crate::outbound::DIAL_TIMEOUT;
use crate::protect::ProtectorHandle;
use crate::resolver::dial;

/// The ceiling `ReadFrom` adds on top of a payload: three reserved bytes, an address type, a length
/// byte, a 255-byte domain and the port.
pub const DATAGRAM_HEADER_MAX: usize = 3 + 1 + 1 + 255 + 2;

/// One connected datagram transport.
pub enum UdpTransport {
    Direct(UdpSocket),
    Socks5(Socks5Udp),
}

pub struct Socks5Udp {
    socket: UdpSocket,
    /// Kept alive: closing it makes the proxy drop the association (and its relay port).
    _control: TcpStream,
    target: String,
}

impl UdpTransport {
    /// The direct transport: a protected socket connected to `target`.
    pub async fn direct(target: SocketAddr, protector: &ProtectorHandle) -> Result<Self, String> {
        let socket = dial::bind_udp(target, protector)
            .map_err(|error| format!("udp dial {target}: {error}"))?;
        let socket =
            UdpSocket::from_std(socket).map_err(|error| format!("udp dial {target}: {error}"))?;
        socket
            .connect(target)
            .await
            .map_err(|error| format!("udp dial {target}: {error}"))?;
        Ok(Self::Direct(socket))
    }

    /// `OpenPacket`: a control connection, `UDP ASSOCIATE`, then a datagram socket to the relay.
    pub async fn socks5(
        target: SocketAddr,
        proxy_address: String,
        username: String,
        password: String,
        protector: &ProtectorHandle,
    ) -> Result<Self, String> {
        let proxy: SocketAddr = proxy_address
            .parse()
            .map_err(|_| format!("invalid proxy address {proxy_address}"))?;
        let mut control = dial::connect_protected(proxy, protector, DIAL_TIMEOUT)
            .await
            .map_err(|error| format!("connect SOCKS5 proxy: {error}"))?;
        let relay = tokio::time::timeout(
            DIAL_TIMEOUT,
            handshake::socks5_udp_associate(&mut control, &username, &password),
        )
        .await
        .unwrap_or_else(|_| Err("SOCKS5 UDP associate: timed out".to_string()))?;
        let relay = resolve_relay(&relay, proxy).await?;
        let socket = dial::bind_udp(relay, protector)
            .map_err(|error| format!("SOCKS5 UDP relay address: {error}"))?;
        let socket = UdpSocket::from_std(socket)
            .map_err(|error| format!("SOCKS5 UDP relay address: {error}"))?;
        socket
            .connect(relay)
            .await
            .map_err(|error| format!("SOCKS5 UDP relay address: {error}"))?;
        Ok(Self::Socks5(Socks5Udp {
            socket,
            _control: control,
            target: target.to_string(),
        }))
    }

    /// Sends one payload; the returned count is the payload's length, not the framed length.
    pub async fn send(&self, payload: &[u8]) -> Result<usize, String> {
        match self {
            Self::Direct(socket) => socket
                .send(payload)
                .await
                .map_err(|error| format!("udp write: {error}")),
            Self::Socks5(state) => {
                let framed = socks5::datagram(&state.target, payload)?;
                state
                    .socket
                    .send(&framed)
                    .await
                    .map_err(|error| format!("udp write: {error}"))?;
                Ok(payload.len())
            }
        }
    }

    /// Receives one payload into `buffer`, returning how many bytes of payload it holds.
    pub async fn recv(&self, buffer: &mut [u8]) -> Result<usize, String> {
        match self {
            Self::Direct(socket) => socket
                .recv(buffer)
                .await
                .map_err(|error| format!("udp read: {error}")),
            Self::Socks5(state) => {
                let mut scratch = vec![0u8; buffer.len() + DATAGRAM_HEADER_MAX];
                let read = state
                    .socket
                    .recv(&mut scratch)
                    .await
                    .map_err(|error| format!("udp read: {error}"))?;
                if read < 4 || scratch[0] != 0 || scratch[1] != 0 || scratch[2] != 0 {
                    return Err("invalid or fragmented SOCKS5 UDP packet".to_string());
                }
                let view = socks5::parse_datagram(&scratch[3..read])?;
                let payload = &scratch[3 + view.offset..read];
                let count = payload.len().min(buffer.len());
                buffer[..count].copy_from_slice(&payload[..count]);
                Ok(count)
            }
        }
    }

    /// Whether the transport speaks SOCKS5 framing (telemetry/tests).
    pub fn is_proxied(&self) -> bool {
        matches!(self, Self::Socks5(_))
    }
}

/// `net.ResolveUDPAddr` for the relay address, with Go's "an unspecified relay means the proxy
/// itself" rule.
async fn resolve_relay(relay: &str, proxy: SocketAddr) -> Result<SocketAddr, String> {
    let parsed: Option<SocketAddr> = relay.parse().ok();
    let mut address = match parsed {
        Some(address) => address,
        None => {
            let resolved = tokio::time::timeout(DIAL_TIMEOUT, tokio::net::lookup_host(relay))
                .await
                .map_err(|_| format!("SOCKS5 UDP relay address: lookup {relay} timed out"))?
                .map_err(|error| format!("SOCKS5 UDP relay address: {error}"))?
                .next();
            resolved
                .ok_or_else(|| format!("SOCKS5 UDP relay address: {relay} resolved to nothing"))?
        }
    };
    if address.ip().is_unspecified() {
        address.set_ip(proxy.ip());
    }
    Ok(address)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn an_unspecified_relay_becomes_the_proxy_address() {
        let proxy: SocketAddr = "127.0.0.1:1080".parse().expect("proxy");
        let relay = resolve_relay("0.0.0.0:5000", proxy).await.expect("relay");
        assert_eq!(relay, "127.0.0.1:5000".parse().expect("relay"));
    }

    #[tokio::test]
    async fn a_literal_relay_is_used_as_is() {
        let proxy: SocketAddr = "127.0.0.1:1080".parse().expect("proxy");
        let relay = resolve_relay("[::1]:5000", proxy).await.expect("relay");
        assert!(relay.is_ipv6());
        assert_eq!(relay.port(), 5000);
    }

    #[tokio::test]
    async fn a_direct_transport_round_trips_one_datagram() {
        let server = tokio::net::UdpSocket::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let address = server.local_addr().expect("addr");
        let transport = UdpTransport::direct(address, &ProtectorHandle::new())
            .await
            .expect("direct");
        assert!(!transport.is_proxied());
        assert_eq!(transport.send(b"ping").await.expect("send"), 4);

        let mut buffer = [0u8; 64];
        let (read, peer) =
            tokio::time::timeout(Duration::from_secs(1), server.recv_from(&mut buffer))
                .await
                .expect("recv")
                .expect("recv");
        assert_eq!(&buffer[..read], b"ping");
        server.send_to(b"pong", peer).await.expect("reply");
        let count = transport.recv(&mut buffer).await.expect("recv");
        assert_eq!(&buffer[..count], b"pong");
    }
}

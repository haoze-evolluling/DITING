use std::net::SocketAddr;

use diting_proxy_core::socks5;
use tokio::net::{TcpStream, UdpSocket};

use crate::outbound::handshake;
use crate::outbound::DIAL_TIMEOUT;
use crate::protect::ProtectorHandle;
use crate::resolver::dial;

pub const DATAGRAM_HEADER_MAX: usize = 3 + 1 + 1 + 255 + 2;

pub enum UdpTransport {
    Direct(UdpSocket),
    Socks5(Socks5Udp),
}

pub struct Socks5Udp {
    socket: UdpSocket,
    _control: TcpStream,
    target: String,
}

impl UdpTransport {
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

    pub fn is_proxied(&self) -> bool {
        matches!(self, Self::Socks5(_))
    }
}

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

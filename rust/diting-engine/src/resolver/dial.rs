use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::sync::{Arc, RwLock};
use std::time::Duration;

use diting_upstream_core::endpoint::dial_address;
use diting_upstream_core::tuning::TUNING;
use socket2::{Domain, Protocol, Socket, Type};
use tokio::net::lookup_host;
use tokio::net::{TcpSocket, TcpStream};
use tokio::time::{sleep, timeout};

use crate::outbound::udp::UdpTransport;
use crate::outbound::{Outbound, Route};
use crate::protect::ProtectorHandle;
use crate::resolver::bootstrap::Bootstrap;

pub fn connect_timeout() -> Duration {
    Duration::from_nanos(TUNING.connect_timeout_ns.max(1) as u64)
}

/// 网络交接瞬间（Wi-Fi ↔ 蜂窝）会短暂出现无路由，稍等后重试即可恢复。
const TRANSIENT_RETRIES: u32 = 2;
const TRANSIENT_DELAY: Duration = Duration::from_millis(150);

fn transient_network_error(message: &str) -> bool {
    message.contains("Network is unreachable")
        || message.contains("Network is down")
        || message.contains("Operation not permitted")
        || message.contains("os error 101")
        || message.contains("os error 100")
        || message.contains("os error 1)")
}

#[derive(Clone)]
pub struct Dialer {
    bootstrap: Arc<Bootstrap>,
    protector: ProtectorHandle,
    outbound: Option<Arc<RwLock<Outbound>>>,
}

impl Dialer {
    pub fn new(bootstrap: Arc<Bootstrap>, protector: ProtectorHandle) -> Self {
        Self {
            bootstrap,
            protector,
            outbound: None,
        }
    }

    pub fn with_outbound(mut self, outbound: Option<Arc<RwLock<Outbound>>>) -> Self {
        self.outbound = outbound;
        self
    }

    fn resolver_route(&self) -> Option<Outbound> {
        let outbound = self
            .outbound
            .as_ref()?
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        outbound.config().resolver_uses_proxy().then_some(outbound)
    }

    pub fn bootstrap(&self) -> &Bootstrap {
        &self.bootstrap
    }

    pub fn protector(&self) -> &ProtectorHandle {
        &self.protector
    }

    pub async fn addresses(&self, host: &str, port: &str) -> Result<Vec<SocketAddr>, String> {
        let mut resolved = host.to_string();
        if host.parse::<IpAddr>().is_err() {
            if let Ok(address) = self.bootstrap.resolve_host(host).await {
                if !address.is_empty() {
                    resolved = address;
                }
            }
        }

        let text = dial_address(host, port, &resolved);
        if let Ok(address) = text.parse::<SocketAddr>() {
            return Ok(vec![address]);
        }

        let Ok(port) = port.parse::<u16>() else {
            return Err(format!("invalid upstream port {port}"));
        };
        match timeout(connect_timeout(), lookup_host((resolved.clone(), port))).await {
            Ok(Ok(addresses)) => {
                let addresses: Vec<SocketAddr> = addresses.collect();
                if addresses.is_empty() {
                    Err(format!("upstream {host} resolved to no address"))
                } else {
                    Ok(addresses)
                }
            }
            Ok(Err(error)) => Err(format!("upstream {host} lookup failed: {error}")),
            Err(_) => Err(format!("upstream {host} lookup timed out")),
        }
    }

    pub async fn resolve(&self, host: &str, port: &str) -> Result<SocketAddr, String> {
        let addresses = self.addresses(host, port).await?;
        addresses
            .into_iter()
            .next()
            .ok_or_else(|| format!("upstream {host} resolved to no address"))
    }

    pub async fn connect_tcp(&self, host: &str, port: &str) -> Result<TcpStream, String> {
        let addresses = self.addresses(host, port).await?;
        let route = self.resolver_route();
        let mut last_error = String::new();
        for round in 0..=TRANSIENT_RETRIES {
            for &address in &addresses {
                let attempt = match &route {
                    Some(outbound) => outbound.dial_tcp(Route::Proxy, address).await,
                    None => self.tcp(address).await.map_err(|error| error.to_string()),
                };
                match attempt {
                    Ok(stream) => return Ok(stream),
                    Err(error) => last_error = error,
                }
            }
            if round == TRANSIENT_RETRIES || !transient_network_error(&last_error) {
                break;
            }
            sleep(TRANSIENT_DELAY * (1 << round)).await;
        }
        Err(last_error)
    }

    pub async fn tcp(&self, target: SocketAddr) -> io::Result<TcpStream> {
        connect_protected(target, &self.protector, connect_timeout()).await
    }

    pub fn resolver_udp_supported(&self) -> bool {
        match self.resolver_route() {
            Some(outbound) => outbound.supports_udp(),
            None => true,
        }
    }

    pub async fn udp_transport(&self, target: SocketAddr) -> Result<UdpTransport, String> {
        match self.resolver_route() {
            Some(outbound) => outbound.dial_udp(Route::Proxy, target).await,
            None => {
                let mut last_error = String::new();
                for round in 0..=TRANSIENT_RETRIES {
                    match UdpTransport::direct(target, &self.protector).await {
                        Ok(transport) => return Ok(transport),
                        Err(error)
                            if round < TRANSIENT_RETRIES
                                && transient_network_error(&error) =>
                        {
                            last_error = error;
                        }
                        Err(error) => return Err(error),
                    }
                    sleep(TRANSIENT_DELAY * (1 << round)).await;
                }
                Err(last_error)
            }
        }
    }
}

pub async fn connect_protected(
    target: SocketAddr,
    protector: &ProtectorHandle,
    budget: Duration,
) -> io::Result<TcpStream> {
    let socket = if target.is_ipv6() {
        TcpSocket::new_v6()?
    } else {
        TcpSocket::new_v4()?
    };
    protect_socket(&socket, protector)?;
    let stream = timeout(budget, socket.connect(target))
        .await
        .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "connect timed out"))??;
    stream.set_nodelay(true)?;
    Ok(stream)
}

pub fn bind_udp(
    target: SocketAddr,
    protector: &ProtectorHandle,
) -> io::Result<std::net::UdpSocket> {
    let domain = if target.is_ipv6() {
        Domain::IPV6
    } else {
        Domain::IPV4
    };
    let socket = Socket::new(domain, Type::DGRAM, Some(Protocol::UDP))?;
    protect_socket(&socket, protector)?;
    let bind = if target.is_ipv6() {
        SocketAddr::new(IpAddr::V6(Ipv6Addr::UNSPECIFIED), 0)
    } else {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0)
    };
    socket.bind(&bind.into())?;
    socket.set_nonblocking(true)?;
    Ok(socket.into())
}

fn protect_socket(socket: &impl SocketFd, protector: &ProtectorHandle) -> io::Result<()> {
    if !protector.is_installed() {
        return Ok(());
    }
    match socket.raw_fd() {
        Some(fd) if fd >= 0 => protector
            .protect_socket(fd)
            .map_err(|error| io::Error::new(io::ErrorKind::PermissionDenied, error)),
        _ => Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "protect needs a socket descriptor",
        )),
    }
}

trait SocketFd {
    fn raw_fd(&self) -> Option<i64>;
}

impl SocketFd for Socket {
    fn raw_fd(&self) -> Option<i64> {
        Some(raw_descriptor(self))
    }
}

impl SocketFd for TcpSocket {
    fn raw_fd(&self) -> Option<i64> {
        Some(raw_descriptor(self))
    }
}

fn raw_descriptor<T>(socket: &T) -> i64
where
    T: RawDescriptor,
{
    socket.raw()
}

trait RawDescriptor {
    fn raw(&self) -> i64;
}

#[cfg(unix)]
impl<T: std::os::fd::AsRawFd> RawDescriptor for T {
    fn raw(&self) -> i64 {
        i64::from(self.as_raw_fd())
    }
}

#[cfg(windows)]
impl<T: std::os::windows::io::AsRawSocket> RawDescriptor for T {
    fn raw(&self) -> i64 {
        self.as_raw_socket() as i64
    }
}

#[cfg(not(any(unix, windows)))]
impl<T> RawDescriptor for T {
    fn raw(&self) -> i64 {
        -1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::logs::DiscardBootstrapSink;
    use crate::protect::Protector;
    use std::sync::atomic::{AtomicI64, Ordering};

    fn dialer() -> Dialer {
        Dialer::new(
            Arc::new(Bootstrap::new(Arc::new(DiscardBootstrapSink))),
            ProtectorHandle::new(),
        )
    }

    #[tokio::test]
    async fn literals_are_used_as_configured() {
        let address = dialer().resolve("127.0.0.1", "53").await.expect("literal");
        assert_eq!(address, "127.0.0.1:53".parse().expect("addr"));
        let address = dialer().resolve("::1", "853").await.expect("v6 literal");
        assert!(address.is_ipv6());
        assert_eq!(address.port(), 853);
    }

    #[tokio::test]
    async fn localhost_falls_through_to_the_system_resolver() {
        let address = dialer().resolve("localhost", "53").await.expect("lookup");
        assert_eq!(address.port(), 53);
        assert!(!dialer()
            .addresses("localhost", "53")
            .await
            .expect("lookup")
            .is_empty());
    }

    #[tokio::test]
    async fn a_tcp_connect_walks_the_whole_address_list() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let port = listener.local_addr().expect("addr").port().to_string();
        let accept = tokio::spawn(async move {
            let _ = listener.accept().await;
        });
        let stream = dialer().connect_tcp("localhost", &port).await;
        assert!(stream.is_ok(), "{:?}", stream.err());
        accept.abort();
    }

    #[tokio::test]
    async fn a_nonsense_port_is_reported() {
        let error = dialer()
            .resolve("127.0.0.1", "dns")
            .await
            .expect_err("bad port");
        assert_eq!(error, "invalid upstream port dns");
    }

    struct Refusing;
    impl Protector for Refusing {
        fn protect(&self, _fd: i64) -> bool {
            false
        }
    }

    struct Counting(AtomicI64);
    impl Protector for Counting {
        fn protect(&self, _fd: i64) -> bool {
            self.0.fetch_add(1, Ordering::Relaxed);
            true
        }
    }

    #[tokio::test]
    async fn a_refused_protect_never_dials() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let address = listener.local_addr().expect("addr");
        let dialer = dialer();
        dialer.protector().install(Arc::new(Refusing));
        let error = dialer.tcp(address).await.expect_err("refused");
        assert_eq!(error.kind(), io::ErrorKind::PermissionDenied);
        assert!(
            tokio::time::timeout(Duration::from_millis(100), listener.accept())
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn a_permissive_protect_runs_before_the_connect() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let address = listener.local_addr().expect("addr");
        let dialer = dialer();
        let counting = Arc::new(Counting(AtomicI64::new(0)));
        dialer.protector().install(counting.clone());
        let accept = tokio::spawn(async move { listener.accept().await });
        let stream = dialer.tcp(address).await.expect("protected dial");
        drop(stream);
        assert_eq!(counting.0.load(Ordering::Relaxed), 1);
        assert!(accept.await.expect("join").is_ok());
    }

    #[tokio::test]
    async fn the_udp_socket_is_protected_too() {
        let dialer = dialer();
        let counting = Arc::new(Counting(AtomicI64::new(0)));
        dialer.protector().install(counting.clone());
        let target: SocketAddr = "127.0.0.1:53".parse().expect("addr");
        let transport = dialer.udp_transport(target).await.expect("udp");
        drop(transport);
        assert_eq!(counting.0.load(Ordering::Relaxed), 1);
    }
}

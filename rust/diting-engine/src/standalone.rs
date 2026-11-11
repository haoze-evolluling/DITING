//! The standalone DNS server: UDP and TCP on IPv4 and IPv6, no TUN required.
//!
//! `StartStandalone`/`StopStandalone` in Go opened four `miekg/dns` servers. The behaviour that has
//! to survive is small but specific:
//!
//! * all four binds are attempted before the engine reports success, and a failed **IPv4** bind fails
//!   the start (the IPv6 pair is optional: a device without IPv6 still serves);
//! * UDP reads with a 4096-byte buffer and answers the client's source address, preserving the source
//!   port (which is what the `/proc/net/udp` UID attribution relies on, once stage 3 needs it);
//! * TCP carries a 2-byte length prefix in both directions and closes an idle connection after
//!   [`TCP_IDLE_TIMEOUT`];
//! * the IPv6 sockets set `IPV6_V6ONLY`, so the dual-stack default cannot steal the IPv4 port.
//!
//! Each request is one task: a query can wait seconds for its upstream, and a single-threaded server
//! loop would serialise every client behind it. A semaphore caps the number of in-flight requests so
//! a flood degrades into dropped queries instead of an unbounded task queue (the engine has no GC).

use std::net::{
    IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, TcpListener as StdTcpListener,
    UdpSocket as StdUdpSocket,
};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use socket2::{Domain, Protocol, Socket, Type};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::Semaphore;
use tokio::task::JoinHandle;

use crate::engine::Engine;
use crate::error::{EngineError, EngineResult};

/// `dnsServerReadTimeout`: an idle TCP client is dropped after 15 s.
pub const TCP_IDLE_TIMEOUT: Duration = Duration::from_secs(15);
/// The UDP read buffer (`dns.MinMsgSize` was 512; a 4096-byte buffer matches the old read cap).
pub const UDP_BUFFER: usize = 4096;
/// In-flight request cap per server instance.
pub const MAX_INFLIGHT: usize = 256;

/// One running server instance.
pub struct Standalone {
    port: u16,
    stopped: Arc<AtomicBool>,
    tasks: Vec<JoinHandle<()>>,
}

impl Standalone {
    pub fn port(&self) -> u16 {
        self.port
    }

    /// Stops every loop and waits for the tasks to unwind, which closes the sockets.
    pub fn stop(mut self) {
        self.stopped.store(true, Ordering::Release);
        for task in self.tasks.drain(..) {
            task.abort();
        }
    }
}

impl Drop for Standalone {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Release);
        for task in self.tasks.drain(..) {
            task.abort();
        }
    }
}

/// Binds and starts the four servers. The IPv4 pair is mandatory; the IPv6 pair is reported and
/// skipped when the device has no IPv6, exactly like the old `logf`-and-continue branch.
pub fn start(engine: Arc<Engine>, port: u16) -> EngineResult<Standalone> {
    let (udp4, tcp4, port) = bind_ipv4_pair(port)?;

    let udp6 = bind_udp(IpAddr::V6(Ipv6Addr::UNSPECIFIED), port, true).ok();
    let tcp6 = bind_tcp(IpAddr::V6(Ipv6Addr::UNSPECIFIED), port, true).ok();
    if udp6.is_none() || tcp6.is_none() {
        engine.log_error(&format!("Standalone IPv6 not available on port {port}"));
    }

    let stopped = Arc::new(AtomicBool::new(false));
    let permits = Arc::new(Semaphore::new(MAX_INFLIGHT));

    let (udp4, tcp4) = to_async(engine.runtime(), udp4, tcp4);
    let udp6 = udp6.map(|socket| to_async_udp(engine.runtime(), socket));
    let tcp6 = tcp6.map(|socket| to_async_tcp(engine.runtime(), socket));

    let mut tasks = Vec::new();
    tasks.push(spawn_udp(
        Arc::clone(&engine),
        udp4,
        permits.clone(),
        stopped.clone(),
    ));
    tasks.push(spawn_tcp(
        Arc::clone(&engine),
        tcp4,
        permits.clone(),
        stopped.clone(),
    ));
    if let Some(udp6) = udp6 {
        tasks.push(spawn_udp(
            Arc::clone(&engine),
            udp6,
            permits.clone(),
            stopped.clone(),
        ));
    }
    if let Some(tcp6) = tcp6 {
        tasks.push(spawn_tcp(
            Arc::clone(&engine),
            tcp6,
            permits.clone(),
            stopped.clone(),
        ));
    }

    Ok(Standalone {
        port,
        stopped,
        tasks,
    })
}

/// Binds the mandatory IPv4 pair on `port`, or on an ephemeral port when `port` is 0.
///
/// Port 0 means "pick one", and the UDP and TCP servers of one engine must share it. The UDP socket
/// takes the ephemeral port and TCP has to follow; on a busy host that TCP port can already be taken
/// (Windows and Linux keep separate ephemeral ranges), so the pair is retried a few times before the
/// start fails.
fn bind_ipv4_pair(port: u16) -> EngineResult<(StdUdpSocket, StdTcpListener, u16)> {
    let attempts = if port == 0 { 8 } else { 1 };
    let mut last_error = String::new();
    for _ in 0..attempts {
        let udp = bind_udp(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port, false).map_err(|error| {
            EngineError::bind(format!(
                "IPv4 UDP Server failed to bind 0.0.0.0:{port}: {error}"
            ))
        })?;
        let actual = if port == 0 {
            udp.local_addr()
                .map_err(|error| {
                    EngineError::bind(format!("IPv4 UDP Server failed to bind: {error}"))
                })?
                .port()
        } else {
            port
        };
        match bind_tcp(IpAddr::V4(Ipv4Addr::UNSPECIFIED), actual, false) {
            Ok(tcp) => return Ok((udp, tcp, actual)),
            Err(error) => {
                last_error = format!("IPv4 TCP Server failed to bind 0.0.0.0:{actual}: {error}");
                if port != 0 {
                    break;
                }
            }
        }
    }
    Err(EngineError::bind(last_error))
}

fn bind_udp(address: IpAddr, port: u16, v6_only: bool) -> std::io::Result<StdUdpSocket> {
    let socket = new_socket(address, Type::DGRAM, v6_only)?;
    socket.bind(&SocketAddr::new(address, port).into())?;
    Ok(socket.into())
}

fn bind_tcp(address: IpAddr, port: u16, v6_only: bool) -> std::io::Result<StdTcpListener> {
    let socket = new_socket(address, Type::STREAM, v6_only)?;
    socket.bind(&SocketAddr::new(address, port).into())?;
    socket.listen(128)?;
    Ok(socket.into())
}

fn new_socket(address: IpAddr, kind: Type, v6_only: bool) -> std::io::Result<Socket> {
    let domain = if address.is_ipv6() {
        Domain::IPV6
    } else {
        Domain::IPV4
    };
    let protocol = if kind == Type::DGRAM {
        Some(Protocol::UDP)
    } else {
        Some(Protocol::TCP)
    };
    let socket = Socket::new(domain, kind, protocol)?;
    if v6_only {
        socket.set_only_v6(true)?;
    }
    socket.set_nonblocking(true)?;
    Ok(socket)
}

/// Converts the bound std sockets inside the runtime context, which `from_std` requires.
fn to_async(
    runtime: &tokio::runtime::Runtime,
    udp: StdUdpSocket,
    tcp: StdTcpListener,
) -> (UdpSocket, TcpListener) {
    let _guard = runtime.enter();
    (
        UdpSocket::from_std(udp).expect("a bound UDP socket is usable"),
        TcpListener::from_std(tcp).expect("a bound TCP listener is usable"),
    )
}

fn to_async_udp(runtime: &tokio::runtime::Runtime, udp: StdUdpSocket) -> UdpSocket {
    let _guard = runtime.enter();
    UdpSocket::from_std(udp).expect("a bound UDP socket is usable")
}

fn to_async_tcp(runtime: &tokio::runtime::Runtime, tcp: StdTcpListener) -> TcpListener {
    let _guard = runtime.enter();
    TcpListener::from_std(tcp).expect("a bound TCP listener is usable")
}

fn spawn_udp(
    engine: Arc<Engine>,
    socket: UdpSocket,
    permits: Arc<Semaphore>,
    stopped: Arc<AtomicBool>,
) -> JoinHandle<()> {
    let receiver = engine.runtime().handle().clone();
    receiver.spawn(async move {
        let socket = Arc::new(socket);
        // A per-request buffer would allocate on every datagram; one buffer per read loop is enough
        // because the read is awaited before the query is handed off.
        let mut buffer = vec![0u8; UDP_BUFFER];
        loop {
            if stopped.load(Ordering::Acquire) {
                return;
            }
            let (read, peer) = match socket.recv_from(&mut buffer).await {
                Ok(received) => received,
                Err(_) => continue,
            };
            let query = buffer[..read].to_vec();
            let engine = Arc::clone(&engine);
            let socket = Arc::clone(&socket);
            let permit = match permits.clone().try_acquire_owned() {
                Ok(permit) => permit,
                // Over the in-flight cap: drop the datagram, the client retries.
                Err(_) => continue,
            };
            tokio::spawn(async move {
                let _permit = permit;
                if let Some(response) = crate::dns::serve(&engine, &query).await {
                    let _ = socket.send_to(&response, peer).await;
                }
            });
        }
    })
}

fn spawn_tcp(
    engine: Arc<Engine>,
    listener: TcpListener,
    permits: Arc<Semaphore>,
    stopped: Arc<AtomicBool>,
) -> JoinHandle<()> {
    let receiver = engine.runtime().handle().clone();
    receiver.spawn(async move {
        loop {
            if stopped.load(Ordering::Acquire) {
                return;
            }
            let (stream, _peer) = match listener.accept().await {
                Ok(accepted) => accepted,
                Err(_) => continue,
            };
            let Ok(permit) = permits.clone().try_acquire_owned() else {
                continue;
            };
            let engine = Arc::clone(&engine);
            tokio::spawn(async move {
                let _permit = permit;
                let _ = serve_tcp_connection(engine, stream).await;
            });
        }
    })
}

/// One TCP connection: length-prefixed queries until the client leaves or idles out.
async fn serve_tcp_connection(engine: Arc<Engine>, mut stream: TcpStream) -> std::io::Result<()> {
    let mut length = [0u8; 2];
    loop {
        let read =
            match tokio::time::timeout(TCP_IDLE_TIMEOUT, stream.read_exact(&mut length)).await {
                Ok(Ok(read)) => read,
                // Timeout, EOF or a broken stream: the connection is done.
                Ok(Err(_)) | Err(_) => return Ok(()),
            };
        if read == 0 {
            return Ok(());
        }
        let size = u16::from_be_bytes(length) as usize;
        if size < 12 {
            return Ok(());
        }
        let mut query = vec![0u8; size];
        if tokio::time::timeout(TCP_IDLE_TIMEOUT, stream.read_exact(&mut query))
            .await
            .is_err()
        {
            return Ok(());
        }
        let Some(response) = crate::dns::serve(&engine, &query).await else {
            continue;
        };
        stream
            .write_all(&(response.len() as u16).to_be_bytes())
            .await?;
        stream.write_all(&response).await?;
        stream.flush().await?;
    }
}

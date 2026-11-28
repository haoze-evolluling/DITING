use std::net::{
    IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, TcpListener as StdTcpListener,
    UdpSocket as StdUdpSocket,
};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use socket2::{Domain, Protocol, Socket, Type};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::{mpsc, Semaphore};
use tokio::task::JoinHandle;

use crate::engine::Engine;
use crate::error::{EngineError, EngineResult};

pub const TCP_IDLE_TIMEOUT: Duration = Duration::from_secs(15);
pub const UDP_BUFFER: usize = 4096;
pub const MAX_INFLIGHT: usize = 256;

pub struct Standalone {
    port: u16,
    stopped: Arc<AtomicBool>,
    tasks: Vec<JoinHandle<()>>,
}

impl Standalone {
    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn stop(mut self) {
        self.shutdown();
    }

    fn shutdown(&mut self) {
        self.stopped.store(true, Ordering::Release);
        let tasks: Vec<JoinHandle<()>> = self.tasks.drain(..).collect();
        for task in &tasks {
            task.abort();
        }
        let deadline = std::time::Instant::now() + Duration::from_millis(250);
        while tasks.iter().any(|task| !task.is_finished()) && std::time::Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

impl Drop for Standalone {
    fn drop(&mut self) {
        self.shutdown();
    }
}

pub fn start(engine: Arc<Engine>, port: u16) -> EngineResult<Standalone> {
    start_on(
        engine,
        port,
        IpAddr::V4(Ipv4Addr::UNSPECIFIED),
        IpAddr::V6(Ipv6Addr::UNSPECIFIED),
    )
}

pub fn start_loopback(engine: Arc<Engine>, port: u16) -> EngineResult<Standalone> {
    start_on(
        engine,
        port,
        IpAddr::V4(Ipv4Addr::LOCALHOST),
        IpAddr::V6(Ipv6Addr::LOCALHOST),
    )
}

fn start_on(
    engine: Arc<Engine>,
    port: u16,
    ipv4: IpAddr,
    ipv6: IpAddr,
) -> EngineResult<Standalone> {
    let (udp4, tcp4, port) = bind_ipv4_pair(ipv4, port)?;

    let udp6 = bind_udp(ipv6, port, true).ok();
    let tcp6 = bind_tcp(ipv6, port, true).ok();
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

fn bind_ipv4_pair(address: IpAddr, port: u16) -> EngineResult<(StdUdpSocket, StdTcpListener, u16)> {
    let attempts = if port == 0 { 8 } else { 1 };
    let mut last_error = String::new();
    for _ in 0..attempts {
        let udp = bind_udp(address, port, false).map_err(|error| {
            EngineError::bind(format!(
                "IPv4 UDP Server failed to bind {address}:{port}: {error}"
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
        match bind_tcp(address, actual, false) {
            Ok(tcp) => return Ok((udp, tcp, actual)),
            Err(error) => {
                last_error = format!("IPv4 TCP Server failed to bind {address}:{actual}: {error}");
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

fn rate_addr(peer: SocketAddr) -> Option<diting_ratelimit_core::Addr> {
    match peer.ip() {
        IpAddr::V4(v4) => diting_ratelimit_core::Addr::from_bytes(&v4.octets()),
        IpAddr::V6(v6) => diting_ratelimit_core::Addr::from_bytes(&v6.octets()),
    }
}

fn now_ns() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as i64)
        .unwrap_or(0)
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
        let mut buffer = vec![0u8; UDP_BUFFER];
        let (replies, mut answered) = mpsc::channel::<(Vec<u8>, SocketAddr)>(MAX_INFLIGHT);
        loop {
            if stopped.load(Ordering::Acquire) {
                return;
            }
            tokio::select! {
                received = socket.recv_from(&mut buffer) => {
                    let (read, peer) = match received {
                        Ok(received) => received,
                        Err(_) => continue,
                    };
                    if !engine.allow_client(rate_addr(peer).as_ref(), now_ns()) {
                        continue;
                    }
                    let query = buffer[..read].to_vec();
                    let engine = Arc::clone(&engine);
                    let replies = replies.clone();
                    let permit = match permits.clone().try_acquire_owned() {
                        Ok(permit) => permit,
                        Err(_) => continue,
                    };
                    tokio::spawn(async move {
                        let _permit = permit;
                        let client = crate::dns::ClientMeta {
                            ip: peer.ip().to_string(),
                            protocol: "udp".to_string(),
                        };
                        if let Some(response) = crate::dns::serve(&engine, &query, &client).await {
                            let _ = replies.send((response, peer)).await;
                        }
                    });
                }
                reply = answered.recv() => {
                    let Some((response, peer)) = reply else { return };
                    let _ = socket.send_to(&response, peer).await;
                }
            }
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
            let (stream, peer) = match listener.accept().await {
                Ok(accepted) => accepted,
                Err(_) => continue,
            };
            if !engine.allow_client(rate_addr(peer).as_ref(), now_ns()) {
                continue;
            }
            let Ok(permit) = permits.clone().try_acquire_owned() else {
                continue;
            };
            let engine = Arc::clone(&engine);
            tokio::spawn(async move {
                let _permit = permit;
                let _ = serve_tcp_connection(engine, stream, peer).await;
            });
        }
    })
}

async fn serve_tcp_connection(
    engine: Arc<Engine>,
    mut stream: TcpStream,
    peer: SocketAddr,
) -> std::io::Result<()> {
    let client = crate::dns::ClientMeta {
        ip: peer.ip().to_string(),
        protocol: "tcp".to_string(),
    };
    let mut length = [0u8; 2];
    loop {
        let read =
            match tokio::time::timeout(TCP_IDLE_TIMEOUT, stream.read_exact(&mut length)).await {
                Ok(Ok(read)) => read,
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
        let Some(response) = crate::dns::serve(&engine, &query, &client).await else {
            continue;
        };
        stream
            .write_all(&(response.len() as u16).to_be_bytes())
            .await?;
        stream.write_all(&response).await?;
        stream.flush().await?;
    }
}

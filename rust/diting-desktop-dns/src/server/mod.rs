pub mod config;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::{watch, Mutex as AsyncMutex, Semaphore};
use tokio::task::{JoinHandle, JoinSet};

use crate::context::{DnsContext, Transport};
use crate::pipeline::Pipeline;

pub use config::ServerConfig;

const MAX_TCP_MESSAGE: usize = 65535;
const UDP_BUFFER: usize = 65535;
const MAX_INFLIGHT: usize = 256;

pub struct DnsServer {
    config: ServerConfig,
    pipeline: Arc<Pipeline>,
    shutdown: Mutex<Option<watch::Sender<bool>>>,
    tasks: Mutex<Vec<JoinHandle<()>>>,
    started: AtomicBool,
    closed: AtomicBool,
    lifecycle: AsyncMutex<()>,
}

pub struct BoundDnsSockets {
    udp: Vec<std::net::UdpSocket>,
    tcp: Vec<std::net::TcpListener>,
}

impl BoundDnsSockets {
    pub fn bind(config: &ServerConfig) -> Result<Self, String> {
        let config = config.clone().normalized();
        let mut udp = Vec::new();
        let mut tcp = Vec::new();
        for address in &config.udp_addresses {
            match std::net::UdpSocket::bind(address.as_str()) {
                Ok(socket) => {
                    socket
                        .set_nonblocking(true)
                        .map_err(|error| format!("configure udp {address} failed: {error}"))?;
                    udp.push(socket);
                }
                Err(_error) if config::is_ipv6(address) => continue,
                Err(error) => return Err(format!("bind udp {address} failed: {error}")),
            }
        }
        for address in &config.tcp_addresses {
            match std::net::TcpListener::bind(address.as_str()) {
                Ok(listener) => {
                    listener
                        .set_nonblocking(true)
                        .map_err(|error| format!("configure tcp {address} failed: {error}"))?;
                    tcp.push(listener);
                }
                Err(_error) if config::is_ipv6(address) => continue,
                Err(error) => return Err(format!("bind tcp {address} failed: {error}")),
            }
        }
        if udp.is_empty() && tcp.is_empty() {
            return Err(
                "failed to bind any DNS listener (all UDP/TCP listeners failed)".to_string(),
            );
        }
        Ok(Self { udp, tcp })
    }

    pub fn is_empty(&self) -> bool {
        self.udp.is_empty() && self.tcp.is_empty()
    }

    pub fn addresses(&self) -> Vec<String> {
        let mut addresses: Vec<String> = self
            .udp
            .iter()
            .filter_map(|socket| socket.local_addr().ok())
            .map(|address| address.to_string())
            .collect();
        addresses.extend(
            self.tcp
                .iter()
                .filter_map(|listener| listener.local_addr().ok())
                .map(|address| address.to_string()),
        );
        addresses.sort();
        addresses.dedup();
        addresses
    }
}

impl DnsServer {
    pub fn new(config: ServerConfig, pipeline: Arc<Pipeline>) -> Self {
        Self {
            config: config.normalized(),
            pipeline,
            shutdown: Mutex::new(None),
            tasks: Mutex::new(Vec::new()),
            started: AtomicBool::new(false),
            closed: AtomicBool::new(false),
            lifecycle: AsyncMutex::new(()),
        }
    }

    pub fn config(&self) -> &ServerConfig {
        &self.config
    }

    pub fn is_serving(&self) -> bool {
        self.started.load(Ordering::SeqCst) && !self.closed.load(Ordering::SeqCst)
    }

    pub async fn start(&self) -> Result<(), String> {
        self.start_inner(None).await
    }

    pub async fn start_with_bound(&self, bound: BoundDnsSockets) -> Result<(), String> {
        self.start_inner(Some(bound)).await
    }

    async fn start_inner(&self, bound: Option<BoundDnsSockets>) -> Result<(), String> {
        let _lifecycle = self.lifecycle.lock().await;
        if self.started.load(Ordering::SeqCst) {
            return Err("server already started".to_string());
        }
        let bound = match bound {
            Some(bound) => bound,
            None => BoundDnsSockets::bind(&self.config)?,
        };
        self.started.store(true, Ordering::SeqCst);
        self.closed.store(false, Ordering::SeqCst);
        let (tx, rx) = watch::channel(false);
        let permits = Arc::new(Semaphore::new(MAX_INFLIGHT));
        let mut tasks = Vec::new();
        let mut bound_count = 0usize;

        for socket in bound.udp {
            let address = socket
                .local_addr()
                .map(|address| address.to_string())
                .unwrap_or_else(|_| "udp socket".to_string());
            match UdpSocket::from_std(socket) {
                Ok(socket) => {
                    bound_count += 1;
                    let socket = Arc::new(socket);
                    let pipeline = self.pipeline.clone();
                    let timeout = self.config.query_timeout();
                    let permits = permits.clone();
                    let mut rx = rx.clone();
                    tasks.push(tokio::spawn(async move {
                        udp_loop(socket, pipeline, permits, timeout, &mut rx).await;
                    }));
                }
                Err(error) => {
                    self.abort_all(&mut tasks).await;
                    *self.shutdown.lock().unwrap() = None;
                    self.started.store(false, Ordering::SeqCst);
                    return Err(format!("adopt udp {address} failed: {error}"));
                }
            }
        }

        for listener in bound.tcp {
            let address = listener
                .local_addr()
                .map(|address| address.to_string())
                .unwrap_or_else(|_| "tcp listener".to_string());
            match TcpListener::from_std(listener) {
                Ok(listener) => {
                    bound_count += 1;
                    let pipeline = self.pipeline.clone();
                    let timeout = self.config.query_timeout();
                    let read_timeout = self.config.read_timeout;
                    let permits = permits.clone();
                    let mut rx = rx.clone();
                    tasks.push(tokio::spawn(async move {
                        tcp_loop(listener, pipeline, permits, timeout, read_timeout, &mut rx).await;
                    }));
                }
                Err(error) => {
                    self.abort_all(&mut tasks).await;
                    *self.shutdown.lock().unwrap() = None;
                    self.started.store(false, Ordering::SeqCst);
                    return Err(format!("adopt tcp {address} failed: {error}"));
                }
            }
        }

        if bound_count == 0 {
            self.abort_all(&mut tasks).await;
            self.started.store(false, Ordering::SeqCst);
            return Err(
                "failed to bind any DNS listener (all UDP/TCP listeners failed)".to_string(),
            );
        }
        *self.shutdown.lock().unwrap() = Some(tx);
        *self.tasks.lock().unwrap() = tasks;
        Ok(())
    }

    pub async fn shutdown(&self) {
        let _lifecycle = self.lifecycle.lock().await;
        if !self.started.swap(false, Ordering::SeqCst) {
            return;
        }
        self.closed.store(true, Ordering::SeqCst);
        if let Some(sender) = self.shutdown.lock().unwrap().take() {
            let _ = sender.send(true);
        }
        let mut tasks = std::mem::take(&mut *self.tasks.lock().unwrap());
        self.stop_tasks(&mut tasks).await;
    }

    async fn abort_all(&self, tasks: &mut Vec<JoinHandle<()>>) {
        let drained: Vec<JoinHandle<()>> = tasks.drain(..).collect();
        for task in &drained {
            task.abort();
        }
        for task in drained {
            let _ = task.await;
        }
    }

    async fn stop_tasks(&self, tasks: &mut Vec<JoinHandle<()>>) {
        let drained: Vec<JoinHandle<()>> = tasks.drain(..).collect();
        if drained.is_empty() {
            return;
        }
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        let mut iter = drained.into_iter();
        let mut remaining = Vec::new();
        while let Some(mut task) = iter.next() {
            if tokio::time::timeout_at(deadline, &mut task).await.is_err() {
                remaining.push(task);
                remaining.extend(iter);
                break;
            }
        }
        for task in &remaining {
            task.abort();
        }
        for task in remaining {
            let _ = task.await;
        }
    }

    pub async fn handle_wire(
        &self,
        request: Vec<u8>,
        client: Option<std::net::SocketAddr>,
        transport: Transport,
    ) -> Vec<u8> {
        self.handle_with_identity(request, client, transport, None)
            .await
    }

    pub async fn handle_with_identity(
        &self,
        request: Vec<u8>,
        client: Option<std::net::SocketAddr>,
        transport: Transport,
        client_id: Option<String>,
    ) -> Vec<u8> {
        let Some(mut ctx) = DnsContext::new(request, client, transport) else {
            return fallback_servfail(&[]);
        };
        if let Some(client_id) = client_id {
            if !client_id.is_empty() {
                ctx.client_id = client_id.clone();
                ctx.set("client_id", client_id);
            }
        }
        let request_copy = ctx.request.clone();
        if !is_standard_query(&request_copy) {
            return fallback_servfail(&request_copy);
        }
        match tokio::time::timeout(self.config.query_timeout(), self.pipeline.execute(&mut ctx))
            .await
        {
            Ok(()) => {}
            Err(_) => {
                ctx.error = Some("query timeout".to_string());
                ctx.fail_servfail();
            }
        }
        let max = ctx.udp_payload_size();
        let mut response = ctx
            .response
            .unwrap_or_else(|| fallback_servfail(&request_copy));
        if transport == Transport::Udp {
            diting_dns_wire::build::truncate_udp(&mut response, max.max(512));
        }
        response
    }
}

fn is_standard_query(wire: &[u8]) -> bool {
    let Some(header) = diting_dns_wire::parse_header(wire) else {
        return false;
    };
    let opcode = (header.flags >> 11) & 0x0f;
    !header.is_response() && opcode == 0 && header.question_count == 1
}

fn fallback_servfail(request: &[u8]) -> Vec<u8> {
    diting_dns_wire::build::MessageBuilder::reply_to(request)
        .and_then(|builder| {
            builder
                .set_rcode(crate::context::RCODE_SERVFAIL)
                .set_recursion_available(true)
                .finish()
        })
        .unwrap_or_default()
}

async fn udp_loop(
    socket: Arc<UdpSocket>,
    pipeline: Arc<Pipeline>,
    permits: Arc<Semaphore>,
    timeout: Duration,
    shutdown: &mut watch::Receiver<bool>,
) {
    let mut buffer = vec![0u8; UDP_BUFFER];
    let mut inflight: JoinSet<()> = JoinSet::new();
    loop {
        while inflight.try_join_next().is_some() {}
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    break;
                }
            }
            received = socket.recv_from(&mut buffer) => {
                let Ok((length, peer)) = received else { continue };
                let Ok(permit) = permits.clone().try_acquire_owned() else { continue };
                let request = buffer[..length].to_vec();
                let socket = socket.clone();
                let pipeline = pipeline.clone();
                inflight.spawn(async move {
                    let _permit = permit;
                    let response = run_query(pipeline, request, Some(peer), Transport::Udp, timeout).await;
                    if !response.is_empty() {
                        let _ = socket.send_to(&response, peer).await;
                    }
                });
            }
        }
    }
    inflight.abort_all();
    while inflight.join_next().await.is_some() {}
}

async fn tcp_loop(
    listener: TcpListener,
    pipeline: Arc<Pipeline>,
    permits: Arc<Semaphore>,
    timeout: Duration,
    read_timeout: Duration,
    shutdown: &mut watch::Receiver<bool>,
) {
    let mut inflight: JoinSet<()> = JoinSet::new();
    loop {
        while inflight.try_join_next().is_some() {}
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    break;
                }
            }
            accepted = listener.accept() => {
                let Ok((stream, peer)) = accepted else { continue };
                let Ok(permit) = permits.clone().try_acquire_owned() else { continue };
                let pipeline = pipeline.clone();
                inflight.spawn(async move {
                    let _permit = permit;
                    let _ = serve_tcp_connection(stream, peer, pipeline, timeout, read_timeout).await;
                });
            }
        }
    }
    inflight.abort_all();
    while inflight.join_next().await.is_some() {}
}

async fn serve_tcp_connection(
    mut stream: TcpStream,
    peer: std::net::SocketAddr,
    pipeline: Arc<Pipeline>,
    timeout: Duration,
    read_timeout: Duration,
) -> std::io::Result<()> {
    loop {
        let mut length_bytes = [0u8; 2];
        let read = tokio::time::timeout(read_timeout, stream.read_exact(&mut length_bytes)).await;
        match read {
            Ok(Ok(_)) => {}
            _ => return Ok(()),
        }
        let length = usize::from(u16::from_be_bytes(length_bytes));
        if length == 0 || length > MAX_TCP_MESSAGE {
            return Ok(());
        }
        let mut request = vec![0u8; length];
        if tokio::time::timeout(read_timeout, stream.read_exact(&mut request))
            .await
            .is_err()
        {
            return Ok(());
        }
        let response = run_query(
            pipeline.clone(),
            request,
            Some(peer),
            Transport::Tcp,
            timeout,
        )
        .await;
        if response.is_empty() || response.len() > MAX_TCP_MESSAGE {
            return Ok(());
        }
        let mut framed = Vec::with_capacity(response.len() + 2);
        framed.extend_from_slice(&(response.len() as u16).to_be_bytes());
        framed.extend_from_slice(&response);
        if tokio::time::timeout(read_timeout, stream.write_all(&framed))
            .await
            .is_err()
        {
            return Ok(());
        }
    }
}

async fn run_query(
    pipeline: Arc<Pipeline>,
    request: Vec<u8>,
    peer: Option<std::net::SocketAddr>,
    transport: Transport,
    timeout: Duration,
) -> Vec<u8> {
    if !is_standard_query(&request) {
        return fallback_servfail(&request);
    }
    let Some(mut ctx) = DnsContext::new(request.clone(), peer, transport) else {
        return fallback_servfail(&request);
    };
    match tokio::time::timeout(timeout, pipeline.execute(&mut ctx)).await {
        Ok(()) => {}
        Err(_) => {
            ctx.error = Some("query timeout".to_string());
            ctx.fail_servfail();
        }
    }
    let max = ctx.udp_payload_size();
    let mut response = ctx.response.unwrap_or_else(|| fallback_servfail(&request));
    if transport == Transport::Udp {
        diting_dns_wire::build::truncate_udp(&mut response, max.max(512));
    }
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pipeline::StageResult;
    use async_trait::async_trait;

    struct Answer;

    #[async_trait]
    impl crate::pipeline::Stage for Answer {
        fn name(&self) -> &'static str {
            "forward"
        }
        async fn before(&self, ctx: &mut DnsContext) -> StageResult {
            ctx.reply_with_rcode(0);
            StageResult::Stop
        }
    }

    fn query() -> Vec<u8> {
        diting_dns_wire::build::MessageBuilder::query("test.local", 1, 1)
            .finish()
            .unwrap()
    }

    #[test]
    fn rejects_answers_and_multiple_questions() {
        let mut response = query();
        response[2] |= 0x80;
        assert!(!is_standard_query(&response));
        let mut two = query();
        two[4] = 0;
        two[5] = 2;
        assert!(!is_standard_query(&two));
        assert!(is_standard_query(&query()));
    }

    #[tokio::test]
    async fn udp_round_trip_on_ephemeral_port() {
        let pipeline = Arc::new(Pipeline::new(vec![Arc::new(Answer)]));
        let probe = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let port = probe.local_addr().unwrap().port();
        drop(probe);
        let server = DnsServer::new(
            ServerConfig {
                udp_addresses: vec![format!("127.0.0.1:{port}")],
                tcp_addresses: Vec::new(),
                ..ServerConfig::default()
            },
            pipeline,
        );
        server.start().await.unwrap();
        let client = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        client
            .send_to(&query(), format!("127.0.0.1:{port}"))
            .await
            .unwrap();
        let mut buffer = [0u8; 512];
        let (length, _) =
            tokio::time::timeout(Duration::from_secs(2), client.recv_from(&mut buffer))
                .await
                .unwrap()
                .unwrap();
        let header = diting_dns_wire::parse_header(&buffer[..length]).unwrap();
        assert!(header.is_response());
        server.shutdown().await;
    }

    #[tokio::test]
    async fn stop_tasks_uses_shared_deadline_for_multiple_stuck_tasks() {
        let pipeline = Arc::new(Pipeline::new(vec![Arc::new(Answer)]));
        let server = DnsServer::new(ServerConfig::default(), pipeline);
        let mut tasks = (0..4)
            .map(|_| tokio::spawn(std::future::pending::<()>()))
            .collect::<Vec<_>>();
        let started = tokio::time::Instant::now();
        server.stop_tasks(&mut tasks).await;
        assert!(tasks.is_empty());
        assert!(
            started.elapsed() < Duration::from_millis(2200),
            "expected shared 1s deadline, got {:?}",
            started.elapsed()
        );
    }
}

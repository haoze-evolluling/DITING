//! Plain DNS service: dual-stack UDP and TCP on the configured addresses.
//!
//! Both transports feed the same pipeline. The socket layer only validates the frame (single
//! standard question), applies the per-query deadline, and truncates UDP replies to the client's
//! advertised payload size — exactly the split the Go `Server` had.

pub mod config;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::watch;
use tokio::task::JoinHandle;

use crate::context::{DnsContext, Transport};
use crate::pipeline::Pipeline;

pub use config::ServerConfig;

/// Maximum DNS message accepted over TCP (RFC 1035 length prefix is 16 bits).
const MAX_TCP_MESSAGE: usize = 65535;
const UDP_BUFFER: usize = 65535;

pub struct DnsServer {
    config: ServerConfig,
    pipeline: Arc<Pipeline>,
    shutdown: Mutex<Option<watch::Sender<bool>>>,
    tasks: Mutex<Vec<JoinHandle<()>>>,
    started: AtomicBool,
    closed: AtomicBool,
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
        }
    }

    pub fn config(&self) -> &ServerConfig {
        &self.config
    }

    pub fn is_serving(&self) -> bool {
        self.started.load(Ordering::SeqCst) && !self.closed.load(Ordering::SeqCst)
    }

    /// Binds every configured socket. IPv6 bind failures are tolerated (some hosts disable IPv6);
    /// a failure on any IPv4 address aborts, matching the Go service.
    pub async fn start(&self) -> Result<(), String> {
        if self.started.swap(true, Ordering::SeqCst) {
            return Err("server already started".to_string());
        }
        self.closed.store(false, Ordering::SeqCst);
        let (tx, rx) = watch::channel(false);
        let mut tasks = Vec::new();
        let mut bound = 0usize;

        for address in &self.config.udp_addresses {
            match UdpSocket::bind(address.as_str()).await {
                Ok(socket) => {
                    bound += 1;
                    let socket = Arc::new(socket);
                    let pipeline = self.pipeline.clone();
                    let timeout = self.config.query_timeout();
                    let mut rx = rx.clone();
                    tasks.push(tokio::spawn(async move {
                        udp_loop(socket, pipeline, timeout, &mut rx).await;
                    }));
                }
                Err(error) => {
                    if config::is_ipv6(address) {
                        continue;
                    }
                    self.abort_all(&mut tasks).await;
                    *self.shutdown.lock().unwrap() = None;
                    self.started.store(false, Ordering::SeqCst);
                    return Err(format!("bind udp {address} failed: {error}"));
                }
            }
        }

        for address in &self.config.tcp_addresses {
            match TcpListener::bind(address.as_str()).await {
                Ok(listener) => {
                    bound += 1;
                    let pipeline = self.pipeline.clone();
                    let timeout = self.config.query_timeout();
                    let read_timeout = self.config.read_timeout;
                    let mut rx = rx.clone();
                    tasks.push(tokio::spawn(async move {
                        tcp_loop(listener, pipeline, timeout, read_timeout, &mut rx).await;
                    }));
                }
                Err(error) => {
                    if config::is_ipv6(address) {
                        continue;
                    }
                    self.abort_all(&mut tasks).await;
                    *self.shutdown.lock().unwrap() = None;
                    self.started.store(false, Ordering::SeqCst);
                    return Err(format!("bind tcp {address} failed: {error}"));
                }
            }
        }

        if bound == 0 {
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

    /// Stops accepting queries and closes all sockets. In-flight handlers finish on their own
    /// deadline; tasks are aborted so shutdown never waits on a stuck upstream.
    pub async fn shutdown(&self) {
        if !self.started.swap(false, Ordering::SeqCst) {
            return;
        }
        self.closed.store(true, Ordering::SeqCst);
        if let Some(sender) = self.shutdown.lock().unwrap().take() {
            let _ = sender.send(true);
        }
        let mut tasks = std::mem::take(&mut *self.tasks.lock().unwrap());
        self.abort_all(&mut tasks).await;
    }

    async fn abort_all(&self, tasks: &mut Vec<JoinHandle<()>>) {
        for task in tasks.drain(..) {
            task.abort();
        }
        // Aborted tasks release their sockets promptly; yield once so bind failures during a
        // restart do not race the old socket teardown.
        tokio::task::yield_now().await;
    }

    /// Runs one request through the pipeline with the configured deadline.
    pub async fn handle_wire(
        &self,
        request: Vec<u8>,
        client: Option<std::net::SocketAddr>,
        transport: Transport,
    ) -> Vec<u8> {
        let Some(mut ctx) = DnsContext::new(request, client, transport) else {
            return fallback_servfail(&[]);
        };
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
    timeout: Duration,
    shutdown: &mut watch::Receiver<bool>,
) {
    let mut buffer = vec![0u8; UDP_BUFFER];
    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    break;
                }
            }
            received = socket.recv_from(&mut buffer) => {
                let Ok((length, peer)) = received else { continue };
                let request = buffer[..length].to_vec();
                let socket = socket.clone();
                let pipeline = pipeline.clone();
                tokio::spawn(async move {
                    let response = run_query(pipeline, request, Some(peer), Transport::Udp, timeout).await;
                    if !response.is_empty() {
                        let _ = socket.send_to(&response, peer).await;
                    }
                });
            }
        }
    }
}

async fn tcp_loop(
    listener: TcpListener,
    pipeline: Arc<Pipeline>,
    timeout: Duration,
    read_timeout: Duration,
    shutdown: &mut watch::Receiver<bool>,
) {
    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    break;
                }
            }
            accepted = listener.accept() => {
                let Ok((stream, peer)) = accepted else { continue };
                let pipeline = pipeline.clone();
                tokio::spawn(async move {
                    let _ = serve_tcp_connection(stream, peer, pipeline, timeout, read_timeout).await;
                });
            }
        }
    }
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
            _ => return Ok(()), // idle timeout or peer closed
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
}

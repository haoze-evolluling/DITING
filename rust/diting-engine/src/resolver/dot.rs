//! DNS over TLS (RFC 7858): the 2-byte framed exchange over a pooled `tokio-rustls` stream.
//!
//! `resolver_dot.go`'s policy half — LIFO reuse, the 15 s idle window, four connections per host,
//! the "keep it or close it" verdict — is [`diting_upstream_core::DotPool`]; this module owns the
//! TLS objects and the queries, keyed by the numeric id the kernel hands back.
//!
//! Two deliberate differences from the Go code, both forced by the stream type:
//!
//! * `isAlive()` probed the socket with a zero read deadline. A TLS stream cannot be peeked without
//!   consuming bytes, so the probe *is* the query: a pooled connection gets the query with the
//!   shorter `dotProbeTimeout` budget, and a failure discards it and dials a fresh one. That is the
//!   same decision the old probe drove, with one round trip instead of one syscall.
//! * Go's `tls.ClientSessionCache` was shared per process; `rustls` puts the session cache inside
//!   the `ClientConfig`, so the resolver's one config carries it.
//!
//! The response-length rule (`0` or `> 4096` is invalid) stays in the kernel, because plain TCP
//! deliberately does not apply it.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use diting_upstream_core::framing::{dot_response_length, encode_length_prefixed, DotLength};
use diting_upstream_core::pool::{Acquired, DotPool};
use diting_upstream_core::tuning::TUNING;
use rustls::pki_types::ServerName;
use rustls::ClientConfig;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::timeout;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

use crate::resolver::dial::Dialer;

/// The idle TLS connections of one resolver, keyed by the kernel's ids.
#[derive(Default)]
struct Pooled {
    streams: HashMap<u64, TlsStream<TcpStream>>,
    next_id: u64,
}

/// The DoT transport: one TLS config plus the idle pool.
pub struct DotClient {
    config: Arc<ClientConfig>,
    pool: DotPool,
    pooled: Mutex<Pooled>,
}

impl DotClient {
    pub fn new(trust: &crate::resolver::trust::UpstreamTrust) -> Self {
        Self {
            config: trust.client_config(&crate::resolver::trust::DOT_ALPN),
            pool: DotPool::new(),
            pooled: Mutex::new(Pooled::default()),
        }
    }

    /// `queryDoTContext`: reuse a pooled connection when the probe query succeeds, otherwise dial.
    pub async fn query(
        &self,
        dialer: &Dialer,
        host: &str,
        port: &str,
        query: &[u8],
    ) -> Result<Vec<u8>, String> {
        let target = dialer.resolve(host, port).await?;
        let key = target.to_string();

        if let Some((id, mut stream)) = self.take(&key) {
            let probe = Duration::from_nanos(TUNING.dot_probe_timeout_ns.max(1) as u64);
            match timeout(probe, exchange(&mut stream, query)).await {
                Ok(Ok(response)) => {
                    self.put(&key, id, stream);
                    return Ok(response);
                }
                // Expired by the kernel window, or the socket died while parked.
                _ => drop(stream),
            }
        }

        let stream = self.dial(dialer, host, port).await?;
        self.exchange_within(&key, stream, query).await
    }

    /// One fresh connection, handshaken with the DoT query budget like `dialFreshDoTConn`.
    async fn dial(
        &self,
        dialer: &Dialer,
        host: &str,
        port: &str,
    ) -> Result<TlsStream<TcpStream>, String> {
        let tcp = dialer
            .connect_tcp(host, port)
            .await
            .map_err(|error| format!("DoT dial: {error}"))?;
        let name = ServerName::try_from(host.to_string())
            .map_err(|error| format!("DoT TLS handshake: {error}"))?;
        let budget = Duration::from_nanos(TUNING.query_timeout_dot_ns.max(1) as u64);
        match timeout(
            budget,
            TlsConnector::from(self.config.clone()).connect(name, tcp),
        )
        .await
        {
            Ok(Ok(stream)) => Ok(stream),
            Ok(Err(error)) => Err(format!("DoT TLS handshake: {error}")),
            Err(_) => Err("DoT TLS handshake: timed out".to_string()),
        }
    }

    /// Executes the query with the DoT budget, then parks the connection for reuse.
    async fn exchange_within(
        &self,
        key: &str,
        mut stream: TlsStream<TcpStream>,
        query: &[u8],
    ) -> Result<Vec<u8>, String> {
        let budget = Duration::from_nanos(TUNING.query_timeout_dot_ns.max(1) as u64);
        let outcome = timeout(budget, exchange(&mut stream, query)).await;
        match outcome {
            Ok(Ok(response)) => {
                let id = self.register();
                self.put(key, id, stream);
                Ok(response)
            }
            Ok(Err(error)) => Err(error),
            Err(_) => Err("DoT read response: timed out".to_string()),
        }
    }

    /// `popIdleDoTConn`'s socket half: pop the newest entry the kernel allows and loop past the
    /// entries whose stream is already gone.
    fn take(&self, key: &str) -> Option<(u64, TlsStream<TcpStream>)> {
        let mut pooled = self.lock();
        loop {
            match self.pool.acquire(key, crate::resolver::now_ms())? {
                Acquired::Idle(id) => {
                    if let Some(stream) = pooled.streams.remove(&id) {
                        return Some((id, stream));
                    }
                    // Expired by the kernel window, or the socket died while parked.
                }
                Acquired::Expired(id) => {
                    pooled.streams.remove(&id);
                }
            }
        }
    }

    /// `putIdleDoTConn`: park the connection when the host has room, otherwise let it drop (which
    /// closes it).
    fn put(&self, key: &str, id: u64, stream: TlsStream<TcpStream>) {
        let mut pooled = self.lock();
        if self.pool.release(key, id, crate::resolver::now_ms()) {
            pooled.streams.insert(id, stream);
        }
    }

    fn register(&self) -> u64 {
        let mut pooled = self.lock();
        pooled.next_id += 1;
        pooled.next_id
    }

    /// Closes every parked connection (`closeDoTConns`).
    pub fn close_all(&self) {
        {
            let mut pooled = self.lock();
            pooled.streams.clear();
        }
        self.pool.close_all();
    }

    /// How many connections are parked for `key` (tests and the diagnostics panel).
    pub fn idle(&self, key: &str) -> u32 {
        self.pool.len(key)
    }

    fn lock(&self) -> MutexGuard<'_, Pooled> {
        self.pooled
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

/// One framed request/response on a live TLS stream.
async fn exchange(stream: &mut TlsStream<TcpStream>, query: &[u8]) -> Result<Vec<u8>, String> {
    let framed = encode_length_prefixed(query);
    stream
        .write_all(&framed)
        .await
        .map_err(|error| format!("DoT write: {error}"))?;

    let mut header = [0u8; 2];
    stream
        .read_exact(&mut header)
        .await
        .map_err(|error| format!("DoT read length: {error}"))?;
    match dot_response_length(&header) {
        Some(DotLength::Valid(length)) => {
            let mut response = vec![0u8; length];
            stream
                .read_exact(&mut response)
                .await
                .map_err(|error| format!("DoT read response: {error}"))?;
            Ok(response)
        }
        Some(DotLength::Invalid(length)) => Err(format!("DoT invalid response length: {length}")),
        None => Err("DoT read length: unreadable header".to_string()),
    }
}

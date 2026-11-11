//! DNS over QUIC (RFC 9250): one bidirectional stream per query on a reused QUIC connection.
//!
//! `resolver_doq.go` kept a single `quic.Connection` per configured endpoint and reopened it when a
//! stream could not be opened; the message is framed with the 2-byte length prefix, the stream is
//! closed for writing after the request, and the response length prefix is stripped only when it
//! declares exactly the remaining bytes (the kernel's `doq_skip`).
//!
//! `quinn` replaces `quic-go`. The endpoint is created lazily inside the query, because building one
//! needs a tokio runtime and `ApplyDNSConfig` runs on the JNI thread: a resolver is configured off
//! the runtime, so nothing here may assume one. The endpoint is kept per address family, so a v6
//! provider does not force a dual-stack socket (`quic-go`'s `Transport{Conn: udpConn}` was bound by
//! the outbound dialer instead).
//!
//! The TLS config is TLS 1.3 only with the `doq` ALPN, which is what `quic-go` required and what
//! RFC 9250 mandates.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Mutex, MutexGuard};
use std::time::Duration;

use diting_upstream_core::framing::{doq_skip, encode_length_prefixed};
use diting_upstream_core::tuning::TUNING;
use quinn::crypto::rustls::QuicClientConfig;
use quinn::{Endpoint, EndpointConfig, IdleTimeout, RecvStream, SendStream, TransportConfig};

use crate::resolver::dial::{self, Dialer};
use crate::resolver::trust::UpstreamTrust;

/// The DoQ transport: a lazily created endpoint per family plus the cached sessions.
pub struct DoqClient {
    config: quinn::ClientConfig,
    endpoint: Mutex<Option<(bool, Endpoint)>>,
    sessions: Mutex<HashMap<String, quinn::Connection>>,
}

impl DoqClient {
    pub fn new(trust: &UpstreamTrust) -> Result<Self, String> {
        let crypto = QuicClientConfig::try_from((*trust.quic_client_config()).clone())
            .map_err(|error| format!("DoQ TLS config: {error}"))?;
        let mut config = quinn::ClientConfig::new(std::sync::Arc::new(crypto));
        let mut transport = TransportConfig::default();
        let idle = IdleTimeout::try_from(Duration::from_nanos(
            TUNING.doq_max_idle_timeout_ns.max(1) as u64,
        ))
        .map_err(|error| format!("DoQ idle timeout: {error}"))?;
        transport.max_idle_timeout(Some(idle));
        config.transport_config(std::sync::Arc::new(transport));
        Ok(Self {
            config,
            endpoint: Mutex::new(None),
            sessions: Mutex::new(HashMap::new()),
        })
    }

    /// `queryDoQContext`. The first stream is opened on the cached session; if opening it fails the
    /// session is reset, a fresh one is dialed and the stream is opened once more (`getOrCreateQUICConn`
    /// after `resetQUICConn` in the old code). A stream that opened but failed to write or read is
    /// reported as is — the Go code did not retry that either.
    pub async fn query(
        &self,
        dialer: &Dialer,
        host: &str,
        port: &str,
        query: &[u8],
    ) -> Result<Vec<u8>, String> {
        let addresses = dialer.addresses(host, port).await?;
        let key = format!("{host}:{port}");
        let budget = Duration::from_nanos(TUNING.query_timeout_doq_ns.max(1) as u64);

        let connection = self.connect(dialer, &key, host, &addresses).await?;
        let (send, recv) = match open_stream(&connection, budget).await {
            Ok(pair) => pair,
            Err(_) => {
                self.forget(&key);
                let connection = self.connect(dialer, &key, host, &addresses).await?;
                match open_stream(&connection, budget).await {
                    Ok(pair) => pair,
                    Err(error) => return Err(format!("DoQ stream: {error}")),
                }
            }
        };

        let response = match tokio::time::timeout(budget, exchange(send, recv, query)).await {
            Ok(result) => result?,
            Err(_) => return Err("DoQ read: timed out".to_string()),
        };

        // RFC 9250 prefixes the message with its length; strip it only when the prefix declares
        // exactly the remaining bytes.
        let skip = doq_skip(&response);
        Ok(response[skip..].to_vec())
    }

    /// The cached session for `key`, dialing one when there is none.
    async fn connect(
        &self,
        dialer: &Dialer,
        key: &str,
        host: &str,
        addresses: &[SocketAddr],
    ) -> Result<quinn::Connection, String> {
        if let Some(connection) = self.lock_sessions().get(key).cloned() {
            if connection.close_reason().is_none() {
                return Ok(connection);
            }
            self.forget(key);
        }

        let budget = Duration::from_nanos(TUNING.connect_timeout_ns.max(1) as u64);
        let mut last_error = String::new();
        for target in addresses {
            let endpoint = self.endpoint_for(dialer, target.is_ipv6())?;
            let connecting = endpoint
                .connect_with(self.config.clone(), *target, host)
                .map_err(|error| format!("DoQ connection: {error}"))?;
            match tokio::time::timeout(budget, connecting).await {
                Ok(Ok(connection)) => {
                    self.lock_sessions()
                        .insert(key.to_string(), connection.clone());
                    return Ok(connection);
                }
                Ok(Err(error)) => last_error = format!("DoQ connection: {error}"),
                Err(_) => last_error = "DoQ connection: timed out".to_string(),
            }
        }
        Err(last_error)
    }

    /// `resetQUICConn`: drop the session so the next query dials a fresh one.
    fn forget(&self, key: &str) {
        if let Some(connection) = self.lock_sessions().remove(key) {
            connection.close(0u32.into(), b"reset");
        }
    }

    /// Closes every session and the endpoint (`Shutdown`).
    pub fn close(&self) {
        for (_, connection) in self
            .sessions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .drain()
        {
            connection.close(0u32.into(), b"shutdown");
        }
        if let Some((_, endpoint)) = self
            .endpoint
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
        {
            endpoint.close(0u32.into(), b"shutdown");
        }
    }

    fn endpoint_for(&self, dialer: &Dialer, ipv6: bool) -> Result<Endpoint, String> {
        let mut slot = self
            .endpoint
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some((family, endpoint)) = slot.as_ref() {
            if *family == ipv6 {
                return Ok(endpoint.clone());
            }
            endpoint.close(0u32.into(), b"family change");
        }
        let bind: SocketAddr = if ipv6 {
            "[::]:0".parse().expect("a valid v6 bind")
        } else {
            "0.0.0.0:0".parse().expect("a valid v4 bind")
        };
        let endpoint = if dialer.protector().is_installed() {
            // QUIC's socket is not connected until the endpoint starts a handshake, so protecting
            // it right after creation is exactly the window `VpnService.protect` needs.
            let socket = dial::bind_udp(bind, dialer.protector())
                .map_err(|error| format!("DoQ packet outbound: {error}"))?;
            let runtime = quinn::default_runtime()
                .ok_or_else(|| "DoQ packet outbound: no async runtime".to_string())?;
            Endpoint::new(EndpointConfig::default(), None, socket, runtime)
                .map_err(|error| format!("DoQ packet outbound: {error}"))?
        } else {
            Endpoint::client(bind).map_err(|error| format!("DoQ packet outbound: {error}"))?
        };
        *slot = Some((ipv6, endpoint.clone()));
        Ok(endpoint)
    }

    fn lock_sessions(&self) -> MutexGuard<'_, HashMap<String, quinn::Connection>> {
        self.sessions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl Drop for DoqClient {
    fn drop(&mut self) {
        self.close();
    }
}

/// `OpenStreamSync` under the DoQ query budget.
async fn open_stream(
    connection: &quinn::Connection,
    budget: Duration,
) -> Result<(SendStream, RecvStream), String> {
    match tokio::time::timeout(budget, connection.open_bi()).await {
        Ok(Ok(pair)) => Ok(pair),
        Ok(Err(error)) => Err(error.to_string()),
        Err(_) => Err("timed out".to_string()),
    }
}

/// One framed request on the opened stream, then the whole response up to the read cap.
async fn exchange(
    mut send: SendStream,
    mut recv: RecvStream,
    query: &[u8],
) -> Result<Vec<u8>, String> {
    send.write_all(&encode_length_prefixed(query))
        .await
        .map_err(|error| format!("DoQ write: {error}"))?;
    send.finish()
        .map_err(|error| format!("DoQ write: {error}"))?;

    recv.read_to_end(TUNING.max_read_bytes.max(1) as usize)
        .await
        .map_err(|error| format!("DoQ read: {error}"))
}

use std::sync::Arc;
use std::time::Duration;

use diting_desktop_core::cert::CertManager;
use quinn::{Endpoint, IdleTimeout, VarInt};
use tokio::sync::watch;
use tokio::task::JoinHandle;

use super::dot::{decode_length, encode_frame};
use super::socket_address;
use super::EncryptedConfig;
use crate::context::Transport;
use crate::server::DnsServer;

const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
const IDLE_TIMEOUT: Duration = Duration::from_secs(60);
const KEEP_ALIVE: Duration = Duration::from_secs(15);
const MAX_INCOMING_STREAMS: u32 = 64;
const DOQ_ALPN: &[u8] = b"doq";
const PROTOCOL_ERROR: u32 = 2;

pub(super) async fn start(
    server: Arc<DnsServer>,
    cert: &CertManager,
    config: Arc<EncryptedConfig>,
    shutdown: watch::Receiver<bool>,
) -> Result<(String, Endpoint, JoinHandle<()>), String> {
    let tls = cert.tls_config(vec![DOQ_ALPN.to_vec()])?;
    let crypto = quinn::crypto::rustls::QuicServerConfig::try_from(tls)
        .map_err(|error| format!("DoQ TLS 配置无效: {error}"))?;

    let mut transport = quinn::TransportConfig::default();
    let idle = IdleTimeout::try_from(IDLE_TIMEOUT)
        .map_err(|error| format!("DoQ 空闲超时无效: {error}"))?;
    transport.max_idle_timeout(Some(idle));
    transport.keep_alive_interval(Some(KEEP_ALIVE));
    transport.max_concurrent_bidi_streams(VarInt::from_u32(MAX_INCOMING_STREAMS));

    let mut server_config = quinn::ServerConfig::with_crypto(Arc::new(crypto));
    server_config.transport_config(Arc::new(transport));

    let address = socket_address(&config.listen_address, config.doq_port)?;
    let socket = address
        .parse()
        .map_err(|error| format!("DoQ 监听地址 {address} 无效: {error}"))?;
    let endpoint = Endpoint::server(server_config, socket)
        .map_err(|error| format!("绑定 DoQ {address} 失败: {error}"))?;
    let local = endpoint
        .local_addr()
        .map_err(|error| format!("读取 DoQ 监听地址失败: {error}"))?
        .to_string();

    let accept_endpoint = endpoint.clone();
    let mut shutdown = shutdown;
    let handle = tokio::spawn(async move {
        loop {
            tokio::select! {
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        break;
                    }
                }
                incoming = accept_endpoint.accept() => {
                    let Some(incoming) = incoming else { break };
                    let server = server.clone();
                    let config = config.clone();
                    let shutdown = shutdown.clone();
                    tokio::spawn(async move {
                        serve_connection(server, config, incoming, shutdown).await;
                    });
                }
            }
        }
        accept_endpoint.close(0u32.into(), b"shutdown");
    });
    Ok((local, endpoint, handle))
}

async fn serve_connection(
    server: Arc<DnsServer>,
    config: Arc<EncryptedConfig>,
    incoming: quinn::Incoming,
    mut shutdown: watch::Receiver<bool>,
) {
    let connection = match tokio::time::timeout(HANDSHAKE_TIMEOUT, incoming).await {
        Ok(Ok(connection)) => connection,
        Ok(Err(error)) => {
            eprintln!("[加密DNS] DoQ 握手失败: {error}");
            return;
        }
        Err(_) => {
            eprintln!("[加密DNS] DoQ 握手超时");
            return;
        }
    };

    let sni = connection.handshake_data().and_then(|data| {
        data.downcast::<quinn::crypto::rustls::HandshakeData>()
            .ok()
            .and_then(|data| data.server_name)
    });
    let client_id = sni
        .as_deref()
        .and_then(|sni| super::client_id::client_id_from_server_name(sni, &config.server_name));
    let timeout = server.config().query_timeout();

    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    break;
                }
            }
            accepted = connection.accept_bi() => {
                match accepted {
                    Ok((send, recv)) => {
                        let server = server.clone();
                        let connection = connection.clone();
                        let client_id = client_id.clone();
                        tokio::spawn(async move {
                            handle_stream(server, connection, send, recv, client_id, timeout).await;
                        });
                    }
                    Err(_) => break,
                }
            }
        }
    }
    connection.close(0u32.into(), b"closed");
}

async fn handle_stream(
    server: Arc<DnsServer>,
    connection: quinn::Connection,
    mut send: quinn::SendStream,
    mut recv: quinn::RecvStream,
    client_id: Option<String>,
    timeout: Duration,
) {
    let peer = connection.remote_address();
    let exchanged = tokio::time::timeout(timeout, async {
        let mut prefix = [0u8; 2];
        recv.read_exact(&mut prefix)
            .await
            .map_err(|_| ProtocolError::Incomplete)?;
        let length = decode_length(prefix).ok_or(ProtocolError::InvalidLength)?;
        let mut request = vec![0u8; length];
        recv.read_exact(&mut request)
            .await
            .map_err(|_| ProtocolError::Incomplete)?;

        let header = diting_dns_wire::parse_header(&request).ok_or(ProtocolError::InvalidQuery)?;
        if header.id != 0 {
            return Err(ProtocolError::InvalidQuery);
        }

        let response = server
            .handle_with_identity(request, Some(peer), Transport::Doq, client_id)
            .await;
        let framed = encode_frame(&response).ok_or(ProtocolError::Incomplete)?;
        send.write_all(&framed)
            .await
            .map_err(|_| ProtocolError::Incomplete)?;
        Ok::<(), ProtocolError>(())
    })
    .await;

    match exchanged {
        Ok(Ok(())) => {
            let _ = send.finish();
        }
        Ok(Err(ProtocolError::InvalidLength | ProtocolError::InvalidQuery)) => {
            connection.close(PROTOCOL_ERROR.into(), b"invalid DoQ query");
        }
        Ok(Err(ProtocolError::Incomplete)) => {
            let _ = send.finish();
        }
        Err(_) => {
            let _ = send.finish();
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum ProtocolError {
    InvalidLength,
    InvalidQuery,
    Incomplete,
}

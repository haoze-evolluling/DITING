use std::sync::Arc;
use std::time::Duration;

use diting_desktop_core::cert::CertManager;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_rustls::TlsAcceptor;

use super::client_id::client_id_from_server_name;
use super::socket_address;
use super::EncryptedConfig;
use crate::context::Transport;
use crate::server::DnsServer;

const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);

pub(super) async fn start(
    server: Arc<DnsServer>,
    cert: &CertManager,
    config: Arc<EncryptedConfig>,
    shutdown: watch::Receiver<bool>,
) -> Result<(String, JoinHandle<()>), String> {
    let tls = cert.tls_config(Vec::new())?;
    let address = socket_address(&config.listen_address, config.dot_port)?;
    let listener = TcpListener::bind(&address)
        .await
        .map_err(|error| format!("绑定 DoT {address} 失败: {error}"))?;
    let local = listener
        .local_addr()
        .map_err(|error| format!("读取 DoT 监听地址失败: {error}"))?
        .to_string();

    let acceptor = TlsAcceptor::from(tls);
    let timeout = server.config().query_timeout();
    let mut shutdown = shutdown;
    let handle = tokio::spawn(async move {
        loop {
            tokio::select! {
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        break;
                    }
                }
                accepted = listener.accept() => {
                    match accepted {
                        Ok((stream, peer)) => {
                            let acceptor = acceptor.clone();
                            let server = server.clone();
                            let config = config.clone();
                            let shutdown = shutdown.clone();
                            tokio::spawn(async move {
                                serve_connection(
                                    stream, peer, acceptor, server, config, timeout, shutdown,
                                )
                                .await;
                            });
                        }
                        Err(error) => {
                            eprintln!("[加密DNS] DoT 接受连接失败: {error}");
                            tokio::time::sleep(Duration::from_millis(50)).await;
                        }
                    }
                }
            }
        }
    });
    Ok((local, handle))
}

async fn serve_connection(
    stream: TcpStream,
    peer: std::net::SocketAddr,
    acceptor: TlsAcceptor,
    server: Arc<DnsServer>,
    config: Arc<EncryptedConfig>,
    timeout: Duration,
    mut shutdown: watch::Receiver<bool>,
) {
    let stream = match tokio::time::timeout(HANDSHAKE_TIMEOUT, acceptor.accept(stream)).await {
        Ok(Ok(stream)) => stream,
        Ok(Err(error)) => {
            eprintln!("[加密DNS] DoT 握手失败: {error}");
            return;
        }
        Err(_) => {
            eprintln!("[加密DNS] DoT 握手超时");
            return;
        }
    };
    let sni = stream
        .get_ref()
        .1
        .server_name()
        .map(|name| name.to_string());
    let client_id = sni
        .as_deref()
        .and_then(|sni| client_id_from_server_name(sni, &config.server_name));
    let mut stream = stream;

    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    return;
                }
            }
            request = read_frame(&mut stream, timeout) => {
                let Some(request) = request else { return };
                let response = server
                    .handle_with_identity(
                        request,
                        Some(peer),
                        Transport::Dot,
                        client_id.clone(),
                    )
                    .await;
                let Some(framed) = encode_frame(&response) else {
                    return;
                };
                if tokio::time::timeout(timeout, stream.write_all(&framed))
                    .await
                    .is_err()
                {
                    return;
                }
            }
        }
    }
}

async fn read_frame<S>(stream: &mut S, timeout: Duration) -> Option<Vec<u8>>
where
    S: AsyncRead + Unpin,
{
    let mut prefix = [0u8; 2];
    match tokio::time::timeout(timeout, stream.read_exact(&mut prefix)).await {
        Ok(Ok(_)) => {}
        _ => return None,
    }
    let length = decode_length(prefix)?;
    let mut request = vec![0u8; length];
    match tokio::time::timeout(timeout, stream.read_exact(&mut request)).await {
        Ok(Ok(_)) => Some(request),
        _ => None,
    }
}

pub(crate) fn decode_length(prefix: [u8; 2]) -> Option<usize> {
    let length = usize::from(u16::from_be_bytes(prefix));
    (length > 0).then_some(length)
}

pub(crate) fn encode_frame(message: &[u8]) -> Option<Vec<u8>> {
    let length = u16::try_from(message.len()).ok()?;
    if length == 0 {
        return None;
    }
    let mut framed = Vec::with_capacity(message.len() + 2);
    framed.extend_from_slice(&length.to_be_bytes());
    framed.extend_from_slice(message);
    Some(framed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn framing_rejects_empty_and_round_trips() {
        assert_eq!(decode_length([0, 0]), None);
        assert_eq!(decode_length([0, 12]), Some(12));
        assert_eq!(encode_frame(&[]), None);
        let framed = encode_frame(&[1, 2, 3]).unwrap();
        assert_eq!(framed, vec![0, 3, 1, 2, 3]);
        assert_eq!(decode_length([framed[0], framed[1]]), Some(3));
        let oversized = vec![0u8; usize::from(u16::MAX) + 1];
        assert_eq!(encode_frame(&oversized), None);
    }
}

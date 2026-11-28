use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, watch, Semaphore};

use crate::engine::{now_ms, Engine};
use crate::netstack::{self, TcpKey};
use crate::outbound::{Outbound, Route};
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::queue::{Event, Events};
use crate::tunnel::stats::TunnelCounters;
use diting_telemetry_core::LogItem;

pub const TCP_BUFFER: usize = 32 * 1024;
pub const UDP_BUFFER: usize = 16 * 1024;
pub const UDP_IDLE: Duration = Duration::from_secs(30);

/// 每个上行连接允许“已从客户端收下、尚未写进上游”的最大字节数。
/// 超过后 netstack 停止收包，让 TCP 窗口把压力传回发送端。
pub const UPLOAD_WINDOW: usize = 256 * 1024;

const HOST_PEEK_SIZE: usize = 4 * 1024;
const HOST_PEEK_TIMEOUT: Duration = Duration::from_secs(3);

/// 上游写连续这么久没有任何进展即判定链路失效。网络切换后旧 socket 收不到 RST，
/// `write_all` 可能无限期挂起；按“每次写调用有进展”计时，慢速但存活的链路不会误杀。
const UPSTREAM_WRITE_STALL: Duration = Duration::from_secs(20);
const UPSTREAM_SHUTDOWN_TIMEOUT: Duration = Duration::from_secs(5);

/// 把整块数据写进上游，单次 `write` 超过 `stall` 没有进展就失败。
async fn write_before_stall<W>(
    writer: &mut W,
    mut data: &[u8],
    stall: Duration,
) -> std::io::Result<()>
where
    W: AsyncWriteExt + Unpin,
{
    while !data.is_empty() {
        match tokio::time::timeout(stall, writer.write(data)).await {
            Ok(Ok(0)) => return Err(std::io::ErrorKind::WriteZero.into()),
            Ok(Ok(written)) => data = &data[written..],
            Ok(Err(error)) => return Err(error),
            Err(_) => {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    "upstream write stalled",
                ))
            }
        }
    }
    Ok(())
}

fn is_sniffable_port(port: u16) -> bool {
    port == 443 || port == 80
}

async fn peek_client(inbound: &mut mpsc::Receiver<Inbound>, timeout: Duration) -> (Vec<u8>, bool) {
    let mut peeked = Vec::new();
    match tokio::time::timeout(timeout, inbound.recv()).await {
        Ok(Some(Inbound::Data(data))) => peeked.extend_from_slice(&data),
        Ok(Some(Inbound::Eof)) | Ok(None) => return (peeked, true),
        Err(_) => return (peeked, false),
    }
    while peeked.len() < HOST_PEEK_SIZE {
        match inbound.try_recv() {
            Ok(Inbound::Data(data)) => peeked.extend_from_slice(&data),
            Ok(Inbound::Eof) => return (peeked, true),
            Err(_) => break,
        }
    }
    (peeked, false)
}

fn sniff_host(bytes: &[u8]) -> Option<String> {
    if bytes.is_empty() {
        return None;
    }
    let sniffed = diting_sniffer_core::classify(bytes);
    if sniffed.host.is_empty() {
        return None;
    }
    let host = String::from_utf8_lossy(&sniffed.host)
        .trim()
        .trim_end_matches('.')
        .to_ascii_lowercase();
    if host.is_empty() {
        None
    } else {
        Some(host)
    }
}

fn log_conn_block(engine: &Engine, key: &TcpKey, uid: i32, host: &str, reason: &str) {
    let dest = netstack::socket_addr(key.local);
    engine.logs().push(LogItem {
        domain: host.to_string(),
        blocked: true,
        query_type: 0,
        response_time_ms: 0,
        app_name: engine.display_name(uid),
        resolved_ips: dest.to_string(),
        blocked_by: format!("conn:host:{reason}"),
        error_message: String::new(),
        cached: false,
        timestamp_ms: now_ms(),
        ttl: 0,
        ..LogItem::default()
    });
}

#[allow(clippy::too_many_arguments)]
pub async fn relay_tcp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
    key: TcpKey,
    uid: i32,
    mut inbound: mpsc::Receiver<Inbound>,
    credit: Arc<Semaphore>,
    // 上行信用窗口由 netstack 挂载；MITM 回退路径没有挂载，传 None。
    upload: Option<Arc<Semaphore>>,
    // 网络切换中止流时置位；两个方向都据此退出并关闭上游 socket。
    cancel: watch::Receiver<bool>,
) {
    let (peeked, saw_eof) =
        if is_sniffable_port(key.local.port) && engine.policy().filtering_active() {
            let (bytes, eof) = peek_client(&mut inbound, HOST_PEEK_TIMEOUT).await;
            if let Some(host) = sniff_host(&bytes) {
                let app = engine.app_name(uid);
                if let Some(verdict) = engine.policy().evaluate(&host, &app, 0) {
                    if verdict.blocked {
                        log_conn_block(&engine, &key, uid, &host, &verdict.reason);
                        events.push_command(Event::Abort(key));
                        return;
                    }
                }
            }
            (bytes, eof)
        } else {
            (Vec::new(), false)
        };

    let target = netstack::socket_addr(key.local);
    let outbound = engine.outbound();
    let route = outbound.route_for(uid);
    let stream = match outbound.dial_tcp(route, target).await {
        Ok(stream) => stream,
        Err(error) => {
            counters
                .relay_unavailable
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            engine.log_error(&format!(
                "[TcpStack] upstream dial {target} failed: {error}"
            ));
            events.push_command(Event::Abort(key));
            return;
        }
    };

    let (mut upstream_read, mut upstream_write) = stream.into_split();

    let mut upstream_cancel = cancel.clone();
    let client_to_upstream = tokio::spawn(async move {
        if !peeked.is_empty() {
            if write_before_stall(&mut upstream_write, &peeked, UPSTREAM_WRITE_STALL)
                .await
                .is_err()
            {
                return false;
            }
            if let Some(upload) = &upload {
                upload.add_permits(peeked.len());
            }
        }
        if !saw_eof {
            loop {
                let data = tokio::select! {
                    // 中止（网络切换）：RST 由栈线程统一补发，这里直接收工。
                    _ = upstream_cancel.changed() => return true,
                    item = inbound.recv() => match item {
                        Some(Inbound::Data(data)) => data,
                        _ => break,
                    },
                };
                if write_before_stall(&mut upstream_write, &data, UPSTREAM_WRITE_STALL)
                    .await
                    .is_err()
                {
                    return false;
                }
                if let Some(upload) = &upload {
                    upload.add_permits(data.len());
                }
            }
        }
        let _ = tokio::time::timeout(UPSTREAM_SHUTDOWN_TIMEOUT, upstream_write.shutdown()).await;
        true
    });

    let downstream_engine = Arc::clone(&engine);
    let downstream_events = Arc::clone(&events);
    let mut downstream_cancel = cancel;
    let upstream_to_client = tokio::spawn(async move {
        let mut buffer = vec![0u8; TCP_BUFFER];
        let mut cancelled = false;
        loop {
            let read = tokio::select! {
                _ = downstream_cancel.changed() => {
                    cancelled = true;
                    break;
                }
                read = upstream_read.read(&mut buffer) => read,
            };
            match read {
                Ok(0) => break,
                Ok(read) => {
                    downstream_engine.traffic().record(uid, 0, read as i64);
                    let permit = tokio::select! {
                        _ = downstream_cancel.changed() => {
                            cancelled = true;
                            break;
                        }
                        permit = credit.acquire_many(read as u32) => match permit {
                            Ok(permit) => permit,
                            Err(_) => break,
                        },
                    };
                    permit.forget();
                    downstream_events.push_command(Event::Write(
                        key,
                        buffer[..read].to_vec(),
                        Some(Arc::clone(&credit)),
                    ));
                }
                Err(_) => break,
            }
        }
        // 被中止时栈线程已经清理了这一流，不能再补事件：同键的新流可能已经建立。
        if !cancelled {
            downstream_events.push_command(Event::CloseWrite(key));
        }
    });

    let (forwarded, _) = tokio::join!(client_to_upstream, upstream_to_client);
    if !forwarded.unwrap_or(false) {
        events.push_command(Event::Abort(key));
    }
}

pub async fn relay_udp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
    key: TcpKey,
    uid: i32,
    generation: u64,
    mut inbound: mpsc::Receiver<Vec<u8>>,
) {
    let target = netstack::socket_addr(key.local);
    let outbound: Outbound = engine.outbound();
    let route: Route = outbound.route_for(uid);
    if route == Route::Proxy && !outbound.supports_udp() {
        counters
            .relay_unavailable
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        engine.log_error(&format!(
            "[FullTunnel] UDP {target}: outbound proxy does not support UDP"
        ));
        events.push_command(Event::UdpExpire { key, generation });
        return;
    }
    let transport = match outbound.dial_udp(route, target).await {
        Ok(transport) => transport,
        Err(error) => {
            counters
                .relay_unavailable
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            engine.log_error(&format!("[FullTunnel] UDP dial {target}: {error}"));
            events.push_command(Event::UdpExpire { key, generation });
            return;
        }
    };

    let mut buffer = vec![0u8; UDP_BUFFER];
    loop {
        tokio::select! {
            outgoing = inbound.recv() => {
                match outgoing {
                    Some(payload) => {
                        if let Err(error) = transport.send(&payload).await {
                            engine.log_error(&format!("[FullTunnel] UDP {target}: {error}"));
                            break;
                        }
                    }
                    None => break,
                }
            }
            incoming = transport.recv(&mut buffer) => {
                match incoming {
                    Ok(0) => {}
                    Ok(read) => {
                        engine.traffic().record(uid, 0, read as i64);
                        events.push_command(Event::Datagram {
                            local: key.local,
                            peer: key.remote,
                            payload: buffer[..read].to_vec(),
                        });
                    }
                    Err(error) => {
                        engine.log_error(&format!("[FullTunnel] UDP {target}: {error}"));
                        break;
                    }
                }
            }
            _ = tokio::time::sleep(UDP_IDLE) => break,
        }
    }
    events.push_command(Event::UdpExpire { key, generation });
}

#[cfg(test)]
mod tests {
    use std::pin::Pin;
    use std::task::{Context, Poll};
    use std::time::Duration;

    use super::{is_sniffable_port, sniff_host, write_before_stall};

    struct OneByte;

    impl tokio::io::AsyncWrite for OneByte {
        fn poll_write(
            self: Pin<&mut Self>,
            _cx: &mut Context<'_>,
            buf: &[u8],
        ) -> Poll<std::io::Result<usize>> {
            Poll::Ready(Ok(if buf.is_empty() { 0 } else { 1 }))
        }

        fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }

        fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }

    struct Stalled;

    impl tokio::io::AsyncWrite for Stalled {
        fn poll_write(
            self: Pin<&mut Self>,
            _cx: &mut Context<'_>,
            _buf: &[u8],
        ) -> Poll<std::io::Result<usize>> {
            Poll::Pending
        }

        fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }

        fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
            Poll::Ready(Ok(()))
        }
    }

    #[tokio::test]
    async fn a_slow_but_progressing_write_is_not_called_stalled() {
        let mut writer = OneByte;
        write_before_stall(&mut writer, b"hello", Duration::from_secs(1))
            .await
            .expect("every chunk makes progress");
    }

    #[tokio::test]
    async fn a_write_without_progress_times_out_instead_of_hanging() {
        let mut writer = Stalled;
        let error = write_before_stall(&mut writer, b"hello", Duration::from_millis(10))
            .await
            .expect_err("a stuck socket must fail");
        assert_eq!(error.kind(), std::io::ErrorKind::TimedOut);
    }

    #[test]
    fn only_80_and_443_are_sniffed() {
        assert!(is_sniffable_port(80));
        assert!(is_sniffable_port(443));
        assert!(!is_sniffable_port(53));
        assert!(!is_sniffable_port(8080));
    }

    #[test]
    fn http_host_is_extracted_and_lowercased() {
        let request = b"GET /ad.js HTTP/1.1\r\nHost: Ads.Example\r\n\r\n";
        assert_eq!(sniff_host(request).as_deref(), Some("ads.example"));
    }

    #[test]
    fn unknown_and_empty_have_no_host() {
        assert!(sniff_host(b"").is_none());
        assert!(sniff_host(b"\x00\x01\x02not-a-handshake").is_none());
    }
}

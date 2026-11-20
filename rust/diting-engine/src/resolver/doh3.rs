use std::net::SocketAddr;
use std::sync::{Mutex, MutexGuard};
use std::time::Duration;

use quinn::crypto::rustls::QuicClientConfig;
use quinn::{Endpoint, EndpointConfig, IdleTimeout, TransportConfig};

use crate::resolver::dial::{self, Dialer};
use crate::resolver::session::take_live_session;
use crate::resolver::trust::UpstreamTrust;

pub struct Doh3Client {
    config: quinn::ClientConfig,
    endpoint: Mutex<Option<(bool, Endpoint)>>,
    sessions: Mutex<std::collections::HashMap<String, quinn::Connection>>,
}

impl Doh3Client {
    pub fn new(trust: &UpstreamTrust) -> Result<Self, String> {
        let crypto = QuicClientConfig::try_from((*trust.h3_client_config()).clone())
            .map_err(|error| format!("DoH3 TLS config: {error}"))?;
        let mut config = quinn::ClientConfig::new(std::sync::Arc::new(crypto));
        let mut transport = TransportConfig::default();
        let idle = IdleTimeout::try_from(Duration::from_secs(30))
            .map_err(|error| format!("DoH3 idle timeout: {error}"))?;
        transport.max_idle_timeout(Some(idle));
        config.transport_config(std::sync::Arc::new(transport));
        Ok(Self {
            config,
            endpoint: Mutex::new(None),
            sessions: Mutex::new(std::collections::HashMap::new()),
        })
    }

    pub async fn query(
        &self,
        dialer: &Dialer,
        host: &str,
        port: u16,
        path: &str,
        query: &[u8],
    ) -> Result<Vec<u8>, String> {
        let addresses = dialer.addresses(host, &port.to_string()).await?;
        let connection = self.connect(dialer, host, port, &addresses).await?;
        let (mut send, mut recv) = connection
            .open_bi()
            .await
            .map_err(|error| format!("DoH3 open stream: {error}"))?;
        let request = build_request(host, port, path, query);
        send.write_all(&request)
            .await
            .map_err(|error| format!("DoH3 write: {error}"))?;
        send.finish()
            .map_err(|error| format!("DoH3 write: {error}"))?;
        let response = recv
            .read_to_end(1 << 20)
            .await
            .map_err(|error| format!("DoH3 read: {error}"))?;
        extract_data(&response)
    }

    async fn connect(
        &self,
        dialer: &Dialer,
        host: &str,
        port: u16,
        addresses: &[SocketAddr],
    ) -> Result<quinn::Connection, String> {
        let key = format!("{host}:{port}");
        if let Some(connection) = self.live_session(&key) {
            return Ok(connection);
        }
        let mut last_error = String::new();
        let per_attempt = if addresses.len() > 1 {
            Duration::from_millis(800)
        } else {
            Duration::from_secs(10)
        };
        for target in addresses {
            let endpoint = self.endpoint_for(dialer, target.is_ipv6())?;
            let connecting = endpoint
                .connect_with(self.config.clone(), *target, host)
                .map_err(|error| format!("DoH3 connection: {error}"))?;
            match tokio::time::timeout(per_attempt, connecting).await {
                Ok(Ok(connection)) => {
                    if let Err(error) = setup_connection(&connection).await {
                        last_error = error;
                        continue;
                    }
                    self.lock_sessions().insert(key.clone(), connection.clone());
                    return Ok(connection);
                }
                Ok(Err(error)) => last_error = format!("DoH3 connection: {error}"),
                Err(_) => last_error = "DoH3 connection: timed out".to_string(),
            }
        }
        Err(last_error)
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
            let socket = dial::bind_udp(bind, dialer.protector())
                .map_err(|error| format!("DoH3 packet outbound: {error}"))?;
            let runtime = quinn::default_runtime()
                .ok_or_else(|| "DoH3 packet outbound: no async runtime".to_string())?;
            Endpoint::new(EndpointConfig::default(), None, socket, runtime)
                .map_err(|error| format!("DoH3 packet outbound: {error}"))?
        } else {
            Endpoint::client(bind).map_err(|error| format!("DoH3 packet outbound: {error}"))?
        };
        *slot = Some((ipv6, endpoint.clone()));
        Ok(endpoint)
    }

    fn live_session(&self, key: &str) -> Option<quinn::Connection> {
        let mut sessions = self.lock_sessions();
        take_live_session(&mut sessions, key, |connection| {
            connection.close_reason().is_some()
        })
    }

    fn lock_sessions(
        &self,
    ) -> MutexGuard<'_, std::collections::HashMap<String, quinn::Connection>> {
        self.sessions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }
}

impl Drop for Doh3Client {
    fn drop(&mut self) {
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
}

async fn setup_connection(connection: &quinn::Connection) -> Result<(), String> {
    let mut control = connection
        .open_uni()
        .await
        .map_err(|error| format!("DoH3 control stream: {error}"))?;
    control
        .write_all(&[0x00, 0x04, 0x00])
        .await
        .map_err(|error| format!("DoH3 control write: {error}"))?;
    control
        .finish()
        .map_err(|error| format!("DoH3 control write: {error}"))?;
    for stream_type in [0x02u8, 0x03u8] {
        let mut stream = connection
            .open_uni()
            .await
            .map_err(|error| format!("DoH3 qpack stream: {error}"))?;
        stream
            .write_all(&[stream_type])
            .await
            .map_err(|error| format!("DoH3 qpack write: {error}"))?;
        stream
            .finish()
            .map_err(|error| format!("DoH3 qpack write: {error}"))?;
    }
    Ok(())
}

fn build_request(host: &str, port: u16, path: &str, query: &[u8]) -> Vec<u8> {
    let authority = if port == 443 {
        host.to_string()
    } else {
        format!("{host}:{port}")
    };
    let mut section = vec![0x00, 0x00];
    for (name, value) in [
        (":method", "POST"),
        (":scheme", "https"),
        (":authority", authority.as_str()),
        (":path", path),
        ("content-type", "application/dns-message"),
        ("accept", "application/dns-message"),
    ] {
        qpack_literal(&mut section, name, value);
    }
    let mut out = Vec::new();
    frame(&mut out, 0x01, &section);
    frame(&mut out, 0x00, query);
    out
}

fn qpack_literal(out: &mut Vec<u8>, name: &str, value: &str) {
    prefix_int(out, name.len(), 3, 0x20);
    out.extend_from_slice(name.as_bytes());
    prefix_int(out, value.len(), 7, 0x00);
    out.extend_from_slice(value.as_bytes());
}

fn prefix_int(out: &mut Vec<u8>, value: usize, prefix_bits: u8, first: u8) {
    let max = (1usize << prefix_bits) - 1;
    if value < max {
        out.push(first | value as u8);
        return;
    }
    out.push(first | max as u8);
    let mut rest = value - max;
    while rest >= 128 {
        out.push((rest as u8 & 0x7f) | 0x80);
        rest >>= 7;
    }
    out.push(rest as u8);
}

fn frame(out: &mut Vec<u8>, kind: u64, payload: &[u8]) {
    varint(out, kind);
    varint(out, payload.len() as u64);
    out.extend_from_slice(payload);
}

fn varint(out: &mut Vec<u8>, value: u64) {
    if value < 64 {
        out.push(value as u8);
    } else if value < 16_384 {
        out.push((0x40 | (value >> 8)) as u8);
        out.push(value as u8);
    } else if value < 1_073_741_824 {
        out.push((0x80 | (value >> 24)) as u8);
        out.push((value >> 16) as u8);
        out.push((value >> 8) as u8);
        out.push(value as u8);
    } else {
        out.push((0xc0 | (value >> 56)) as u8);
        for shift in (0..7).rev() {
            out.push((value >> (8 * shift)) as u8);
        }
    }
}

fn read_varint(buf: &[u8]) -> Option<(u64, usize)> {
    let first = *buf.first()?;
    let len = 1usize << (first >> 6);
    if buf.len() < len {
        return None;
    }
    let mut value = (first & 0x3f) as u64;
    for byte in &buf[1..len] {
        value = (value << 8) | *byte as u64;
    }
    Some((value, len))
}

fn extract_data(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let mut rest = bytes;
    let mut data = Vec::new();
    while !rest.is_empty() {
        let (kind, used) = read_varint(rest).ok_or_else(|| "DoH3 frame type".to_string())?;
        rest = &rest[used..];
        let (len, used) = read_varint(rest).ok_or_else(|| "DoH3 frame length".to_string())?;
        rest = &rest[used..];
        let len = len as usize;
        if rest.len() < len {
            break;
        }
        let payload = &rest[..len];
        rest = &rest[len..];
        if kind == 0x00 {
            data.extend_from_slice(payload);
        }
    }
    if data.is_empty() {
        Err("DoH3 response carried no DATA".to_string())
    } else {
        Ok(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn varint_round_trips_every_width() {
        for value in [0u64, 63, 64, 16_383, 16_384, 1_073_741_823, 1_073_741_824] {
            let mut out = Vec::new();
            varint(&mut out, value);
            assert_eq!(read_varint(&out), Some((value, out.len())));
        }
    }

    #[test]
    fn request_frames_parse_back_to_the_query() {
        let request = build_request("dns.example", 443, "/dns-query", b"QUERY");
        let (kind, used) = read_varint(&request).expect("HEADERS type");
        assert_eq!(kind, 0x01);
        let (len, more) = read_varint(&request[used..]).expect("HEADERS length");
        let after_headers = used + more + len as usize;
        let (data_kind, n) = read_varint(&request[after_headers..]).expect("DATA type");
        assert_eq!(data_kind, 0x00);
        let (data_len, n2) = read_varint(&request[after_headers + n..]).expect("DATA length");
        let start = after_headers + n + n2;
        assert_eq!(&request[start..start + data_len as usize], b"QUERY");
    }

    #[test]
    fn extract_data_skips_a_headers_frame() {
        let mut stream = Vec::new();
        frame(&mut stream, 0x01, b"\x00\x00");
        frame(&mut stream, 0x00, b"DNS");
        assert_eq!(extract_data(&stream).unwrap(), b"DNS");
    }

    #[test]
    fn extract_data_rejects_an_empty_body() {
        let mut stream = Vec::new();
        frame(&mut stream, 0x01, b"\x00\x00");
        assert!(extract_data(&stream).is_err());
    }
}

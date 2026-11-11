//! Stage 4a's loopback peers: echo servers and two fake proxies.
//!
//! Every byte here is real I/O on 127.0.0.1. The SOCKS5 proxy is hand-written on purpose: it lets
//! the tests assert **what the engine asked for** (`targets`) and it can answer `UDP ASSOCIATE` with
//! its own relay socket, which is the part of the proxy contract the engine's framing depends on.
//! The HTTP proxy answers a fixed status and then echoes, so a `403` is as easy to test as a `200`.

use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// A loopback TCP echo server; the returned counter counts accepted connections.
pub fn spawn_tcp_echo() -> (SocketAddr, Arc<AtomicUsize>) {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind the echo server");
    let address = listener.local_addr().expect("addr");
    let accepted = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&accepted);
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            counter.fetch_add(1, Ordering::Relaxed);
            std::thread::spawn(move || {
                let mut buffer = [0u8; 4096];
                loop {
                    match std::io::Read::read(&mut stream, &mut buffer) {
                        Ok(0) | Err(_) => return,
                        Ok(read) => {
                            if std::io::Write::write_all(&mut stream, &buffer[..read]).is_err() {
                                return;
                            }
                        }
                    }
                }
            });
        }
    });
    (address, accepted)
}

/// A loopback UDP echo server; the returned counter counts datagrams.
pub fn spawn_udp_echo() -> (SocketAddr, Arc<AtomicUsize>) {
    let socket = std::net::UdpSocket::bind("127.0.0.1:0").expect("bind the echo server");
    socket
        .set_read_timeout(Some(Duration::from_millis(200)))
        .expect("timeout");
    let address = socket.local_addr().expect("addr");
    let count = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&count);
    std::thread::spawn(move || {
        let mut buffer = [0u8; 4096];
        loop {
            let Ok((read, peer)) = socket.recv_from(&mut buffer) else {
                continue;
            };
            counter.fetch_add(1, Ordering::Relaxed);
            let _ = socket.send_to(&buffer[..read], peer);
        }
    });
    (address, count)
}

/// A fake SOCKS5 proxy: no-auth `CONNECT` (then echoes) and `UDP ASSOCIATE` (echoes framed
/// datagrams back unchanged). `targets` records the `host:port` the engine asked for.
pub struct Socks5Proxy {
    pub address: SocketAddr,
    pub targets: Arc<Mutex<Vec<String>>>,
}

pub fn spawn_socks5_proxy() -> Socks5Proxy {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind the proxy");
    let address = listener.local_addr().expect("addr");
    let relay = std::net::UdpSocket::bind("127.0.0.1:0").expect("bind the relay");
    relay
        .set_read_timeout(Some(Duration::from_millis(200)))
        .expect("timeout");
    let relay_port = relay.local_addr().expect("relay addr").port();
    let targets = Arc::new(Mutex::new(Vec::new()));

    {
        let relay = relay.try_clone().expect("clone the relay");
        std::thread::spawn(move || {
            let mut buffer = [0u8; 4096];
            loop {
                let Ok((read, peer)) = relay.recv_from(&mut buffer) else {
                    continue;
                };
                let _ = relay.send_to(&buffer[..read], peer);
            }
        });
    }

    let recorded = Arc::clone(&targets);
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let recorded = Arc::clone(&recorded);
            std::thread::spawn(move || serve_socks5(&mut stream, &recorded, relay_port));
        }
    });

    Socks5Proxy { address, targets }
}

fn serve_socks5(stream: &mut std::net::TcpStream, recorded: &Mutex<Vec<String>>, relay_port: u16) {
    let mut header = [0u8; 2];
    if std::io::Read::read_exact(stream, &mut header).is_err() {
        return;
    }
    let mut methods = vec![0u8; usize::from(header[1])];
    if std::io::Read::read_exact(stream, &mut methods).is_err() {
        return;
    }
    if std::io::Write::write_all(stream, &[0x05, 0x00]).is_err() {
        return;
    }
    let mut request = [0u8; 4];
    if std::io::Read::read_exact(stream, &mut request).is_err() {
        return;
    }
    let command = request[1];
    let host = match request[3] {
        0x01 => {
            let mut octets = [0u8; 4];
            if std::io::Read::read_exact(stream, &mut octets).is_err() {
                return;
            }
            format!("{}.{}.{}.{}", octets[0], octets[1], octets[2], octets[3])
        }
        0x04 => {
            let mut octets = [0u8; 16];
            if std::io::Read::read_exact(stream, &mut octets).is_err() {
                return;
            }
            std::net::Ipv6Addr::from(octets).to_string()
        }
        0x03 => {
            let mut length = [0u8; 1];
            if std::io::Read::read_exact(stream, &mut length).is_err() {
                return;
            }
            let mut name = vec![0u8; usize::from(length[0])];
            if std::io::Read::read_exact(stream, &mut name).is_err() {
                return;
            }
            String::from_utf8_lossy(&name).into_owned()
        }
        _ => return,
    };
    let mut port = [0u8; 2];
    if std::io::Read::read_exact(stream, &mut port).is_err() {
        return;
    }
    let port = u16::from_be_bytes(port);
    recorded
        .lock()
        .expect("targets")
        .push(format!("{host}:{port}"));

    if command == 0x03 {
        let reply = [
            0x05,
            0x00,
            0x00,
            0x01,
            127,
            0,
            0,
            1,
            (relay_port >> 8) as u8,
            (relay_port & 0xff) as u8,
        ];
        let _ = std::io::Write::write_all(stream, &reply);
        // Keep the control connection open for as long as the association lives.
        let mut sink = [0u8; 64];
        let _ = std::io::Read::read(stream, &mut sink);
        return;
    }

    if std::io::Write::write_all(stream, &[0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]).is_err() {
        return;
    }
    let mut buffer = [0u8; 4096];
    loop {
        match std::io::Read::read(stream, &mut buffer) {
            Ok(0) | Err(_) => return,
            Ok(read) => {
                if std::io::Write::write_all(stream, &buffer[..read]).is_err() {
                    return;
                }
            }
        }
    }
}

/// A fake HTTP CONNECT proxy: answers `status`, then echoes on `200`.
pub fn spawn_http_proxy(status: &str) -> (SocketAddr, Arc<Mutex<Vec<String>>>) {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind the proxy");
    let address = listener.local_addr().expect("addr");
    let targets = Arc::new(Mutex::new(Vec::new()));
    let recorded = Arc::clone(&targets);
    let status = status.to_string();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let recorded = Arc::clone(&recorded);
            let status = status.clone();
            std::thread::spawn(move || {
                let mut head = Vec::new();
                let mut byte = [0u8; 1];
                while !head.ends_with(b"\r\n\r\n") {
                    match std::io::Read::read(&mut stream, &mut byte) {
                        Ok(0) | Err(_) => return,
                        Ok(_) => head.push(byte[0]),
                    }
                }
                let text = String::from_utf8_lossy(&head).into_owned();
                if let Some(line) = text.lines().next() {
                    let mut parts = line.split(' ');
                    let _method = parts.next();
                    if let Some(target) = parts.next() {
                        recorded.lock().expect("targets").push(target.to_string());
                    }
                }
                let reply = format!("HTTP/1.1 {status}\r\nContent-Length: 0\r\n\r\n");
                if std::io::Write::write_all(&mut stream, reply.as_bytes()).is_err() {
                    return;
                }
                if !status.starts_with("200") {
                    return;
                }
                let mut buffer = [0u8; 4096];
                loop {
                    match std::io::Read::read(&mut stream, &mut buffer) {
                        Ok(0) | Err(_) => return,
                        Ok(read) => {
                            if std::io::Write::write_all(&mut stream, &buffer[..read]).is_err() {
                                return;
                            }
                        }
                    }
                }
            });
        }
    });
    (address, targets)
}

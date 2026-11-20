use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use socket2::{Domain, Protocol, SockAddr, Socket, Type};

#[cfg(unix)]
use std::os::unix::io::AsRawFd;
#[cfg(windows)]
use std::os::windows::io::AsRawSocket;

use crate::RawSocket;

pub trait Protector: Send + Sync {
    fn protect(&self, fd: RawSocket) -> bool;
}

#[derive(Debug, Default)]
pub struct Evidence {
    pub protect_calls: AtomicU64,
    pub denied: AtomicU64,
    pub connects: AtomicU64,
    pub connect_failures: AtomicU64,
    pub protect_before_connect: AtomicBool,
}

pub struct Connector {
    protector: Arc<dyn Protector>,
    target: SocketAddr,
    evidence: Arc<Evidence>,
}

impl Connector {
    pub fn new(
        protector: Arc<dyn Protector>,
        target: SocketAddr,
        evidence: Arc<Evidence>,
    ) -> Connector {
        Connector {
            protector,
            target,
            evidence,
        }
    }

    pub fn connect(&self) -> Result<std::net::TcpStream, String> {
        let domain = if self.target.is_ipv4() {
            Domain::IPV4
        } else {
            Domain::IPV6
        };
        let socket = Socket::new(domain, Type::STREAM, Some(Protocol::TCP))
            .map_err(|err| format!("create the outbound socket: {err}"))?;
        let _ = socket.set_tcp_nodelay(true);

        let raw = raw_socket(&socket);
        self.evidence.protect_calls.fetch_add(1, Ordering::SeqCst);
        if !self.protector.protect(raw) {
            self.evidence.denied.fetch_add(1, Ordering::SeqCst);
            return Err("VpnService.protect refused the outbound socket".to_string());
        }
        self.evidence.protect_before_connect.store(
            self.evidence.connects.load(Ordering::SeqCst) == 0,
            Ordering::SeqCst,
        );

        match socket.connect(&SockAddr::from(self.target)) {
            Ok(()) => {}
            Err(err) => {
                self.evidence
                    .connect_failures
                    .fetch_add(1, Ordering::SeqCst);
                return Err(format!("connect {}: {err}", self.target));
            }
        }
        self.evidence.connects.fetch_add(1, Ordering::SeqCst);
        let stream: std::net::TcpStream = socket.into();
        let _ = stream.set_nodelay(true);
        Ok(stream)
    }
}

fn raw_socket(socket: &Socket) -> RawSocket {
    #[cfg(unix)]
    {
        socket.as_raw_fd() as RawSocket
    }
    #[cfg(windows)]
    {
        socket.as_raw_socket() as RawSocket
    }
}

pub struct NoProtection;

impl Protector for NoProtection {
    fn protect(&self, _fd: RawSocket) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    use super::*;

    struct RecordingProtector {
        accept: bool,
        calls: AtomicU64,
        saw_connection_while_protecting: AtomicBool,
        accepted: Arc<AtomicU64>,
    }

    impl Protector for RecordingProtector {
        fn protect(&self, fd: RawSocket) -> bool {
            assert!(fd > 0, "protect must receive a real descriptor, got {fd}");
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.saw_connection_while_protecting
                .store(self.accepted.load(Ordering::SeqCst) == 0, Ordering::SeqCst);
            self.accept
        }
    }

    fn listening_target() -> (SocketAddr, Arc<AtomicU64>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        listener.set_nonblocking(true).expect("nonblocking");
        let addr = listener.local_addr().expect("addr");
        let accepted = Arc::new(AtomicU64::new(0));
        let counter = accepted.clone();
        std::thread::spawn(move || loop {
            match listener.accept() {
                Ok(_stream) => {
                    counter.fetch_add(1, Ordering::SeqCst);
                }
                Err(_) => std::thread::sleep(Duration::from_millis(5)),
            }
        });
        (addr, accepted)
    }

    fn closed_port() -> SocketAddr {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        drop(listener);
        addr
    }

    fn recording(accept: bool, accepted: Arc<AtomicU64>) -> Arc<RecordingProtector> {
        Arc::new(RecordingProtector {
            accept,
            calls: AtomicU64::new(0),
            saw_connection_while_protecting: AtomicBool::new(false),
            accepted,
        })
    }

    #[test]
    fn protect_runs_before_connect_and_the_connection_arrives() {
        let (addr, accepted) = listening_target();
        let protector = recording(true, accepted.clone());
        let evidence = Arc::new(Evidence::default());
        let connector = Connector::new(protector.clone(), addr, evidence.clone());

        let stream = connector.connect().expect("a protected dial succeeds");
        assert!(stream.peer_addr().is_ok());
        assert_eq!(protector.calls.load(Ordering::SeqCst), 1);
        assert!(
            protector
                .saw_connection_while_protecting
                .load(Ordering::SeqCst),
            "protect observed the socket before the dial"
        );
        assert!(evidence.protect_before_connect.load(Ordering::SeqCst));
        assert_eq!(evidence.protect_calls.load(Ordering::SeqCst), 1);
        assert_eq!(evidence.connects.load(Ordering::SeqCst), 1);
        assert_eq!(evidence.denied.load(Ordering::SeqCst), 0);

        for _ in 0..200 {
            if accepted.load(Ordering::SeqCst) > 0 {
                break;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        assert_eq!(accepted.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn a_refused_protect_never_dials() {
        let (addr, accepted) = listening_target();
        let protector = recording(false, accepted.clone());
        let evidence = Arc::new(Evidence::default());
        let connector = Connector::new(protector.clone(), addr, evidence.clone());

        let error = connector.connect().expect_err("fail closed");
        assert!(error.contains("protect"), "got {error}");
        assert_eq!(evidence.protect_calls.load(Ordering::SeqCst), 1);
        assert_eq!(evidence.denied.load(Ordering::SeqCst), 1);
        assert_eq!(evidence.connects.load(Ordering::SeqCst), 0);
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(accepted.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn an_unreachable_target_reports_a_connect_failure_not_a_protect_failure() {
        let addr = closed_port();
        let protector = recording(true, Arc::new(AtomicU64::new(0)));
        let evidence = Arc::new(Evidence::default());
        let connector = Connector::new(protector, addr, evidence.clone());
        let error = connector.connect().expect_err("nothing listens");
        assert!(error.starts_with("connect"), "got {error}");
        assert_eq!(evidence.protect_calls.load(Ordering::SeqCst), 1);
        assert_eq!(evidence.denied.load(Ordering::SeqCst), 0);
        assert_eq!(evidence.connect_failures.load(Ordering::SeqCst), 1);
        assert_eq!(evidence.connects.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn no_protection_is_a_pass_through_for_the_standalone_modes() {
        assert!(NoProtection.protect(0));
    }
}

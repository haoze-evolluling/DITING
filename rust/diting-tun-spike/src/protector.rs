//! `VpnService.protect(fd)` and the dial order that depends on it.
//!
//! A VPN app that dials without protecting the socket sends its own outbound packets back into its
//! own tunnel: the kernel routes them to the TUN device, the engine reads them again, and the flow
//! loops (and burns battery) until something times out. Go handled this by calling
//! `protectFn(fd)` **before** `net.Dialer.Dial`, and by treating a failure as fatal for the flow.
//!
//! Two rules are therefore structural here, not conventional:
//!
//! * [`Connector::connect`] creates the socket, asks the protector, and only then calls `connect`.
//!   The protector receives the raw descriptor of the *unconnected* socket, which is what the
//!   platform API requires.
//! * a refused protect fails closed: no `connect` is attempted, no packet of that flow is forwarded,
//!   and the pipeline stops. Silently falling back to an unprotected dial would leak traffic outside
//!   the VPN, which is worse than a failed flow.
//!
//! [`Evidence`] records the order so a test (and the JVM smoke, through `getStats`) can assert it
//! instead of trusting the comment.

use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use socket2::{Domain, Protocol, SockAddr, Socket, Type};

#[cfg(unix)]
use std::os::unix::io::AsRawFd;
#[cfg(windows)]
use std::os::windows::io::AsRawSocket;

use crate::RawSocket;

/// The Kotlin side of `VpnService.protect(int)`.
///
/// Called on the thread that is about to dial (a flow/worker thread, never a JNI caller thread), so
/// the implementation has to attach to the JVM itself. `true` means "the socket now bypasses the
/// tunnel", `false` (or a Java exception, which the JNI adapter maps to `false`) means "do not dial".
pub trait Protector: Send + Sync {
    fn protect(&self, fd: RawSocket) -> bool;
}

/// What [`Connector`] did, in order, for the tests and the stats document.
#[derive(Debug, Default)]
pub struct Evidence {
    /// Protect calls made (one per dial attempt).
    pub protect_calls: AtomicU64,
    /// Protect calls that returned `false` (or threw): the dial was aborted.
    pub denied: AtomicU64,
    /// TCP connections established after a successful protect.
    pub connects: AtomicU64,
    /// `connect(2)` failures after a successful protect.
    pub connect_failures: AtomicU64,
    /// True when the last protect call happened before any connect attempt.
    pub protect_before_connect: AtomicBool,
}

/// Dials one protected TCP connection, in the order the platform requires.
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

    /// Protect, then connect. `Err` text is what `getStats` reports.
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
        // Order matters: the descriptor is unprotected until Kotlin says otherwise, so the connect
        // must be strictly after it. There is no path from here to `connect` that skips this.
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

/// `VpnService` is not running (host tests, or the standalone DNS mode): nothing to protect.
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

    /// Records every protect call and whether a connection already existed at that moment.
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
            // The listener has accepted nothing yet: the connector cannot have dialled.
            self.saw_connection_while_protecting
                .store(self.accepted.load(Ordering::SeqCst) == 0, Ordering::SeqCst);
            self.accept
        }
    }

    /// A listening target: accepts in the background and counts the connections.
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

    /// A closed port: binding and dropping leaves nothing to connect to.
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
        // Nothing can have reached the listener, because `connect` was never called.
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(accepted.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn an_unreachable_target_reports_a_connect_failure_not_a_protect_failure() {
        // A protected dial to a port nobody listens on: connect fails, protect does not.
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

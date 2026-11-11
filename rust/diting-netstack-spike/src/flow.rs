//! Flow records and counters, mirroring the semantics the Go engine keeps in its flow tables.
//!
//! The Go side tracks each flow in `engine_full_tunnel.go` (`tcpFlow` / `udpFlow`), counts bytes in
//! `traffic_tracker.go` and keys the connection log on the 4-tuple. The names here follow the same
//! vocabulary so the port stays mechanical.

use std::collections::VecDeque;

use smoltcp::iface::SocketHandle;
use smoltcp::socket::tcp;
use smoltcp::time::Instant;
use smoltcp::wire::IpEndpoint;

/// The 4-tuple of one proxied TCP connection: the destination the client asked for and the client
/// itself. `local` is the original destination (which the listener adopts verbatim), `remote` the
/// client endpoint as seen by the TUN.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TcpKey {
    pub local: IpEndpoint,
    pub remote: IpEndpoint,
}

impl TcpKey {
    pub fn new(local: IpEndpoint, remote: IpEndpoint) -> Self {
        Self { local, remote }
    }
}

/// One proxied TCP connection.
pub struct TcpFlow {
    pub key: TcpKey,
    pub(crate) handle: SocketHandle,
    /// Bytes dequeued from the socket and waiting for the relay loop. Bounded by
    /// [`crate::Limits::flow_buffer_bytes`]; overflow aborts the flow instead of growing the heap.
    pub recv: VecDeque<u8>,
    pub(crate) state: tcp::State,
    pub(crate) may_recv: bool,
    pub(crate) may_send: bool,
    pub(crate) last_active: Instant,
    pub(crate) closed: bool,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
}

impl TcpFlow {
    pub(crate) fn new(key: TcpKey, handle: SocketHandle, now: Instant) -> Self {
        Self {
            key,
            handle,
            recv: VecDeque::new(),
            state: tcp::State::Listen,
            may_recv: true,
            may_send: true,
            last_active: now,
            closed: false,
            rx_bytes: 0,
            tx_bytes: 0,
        }
    }

    pub fn state(&self) -> tcp::State {
        self.state
    }

    /// `false` once the connection is gone: the socket hit `Closed` and was removed from the set.
    pub fn is_closed(&self) -> bool {
        self.closed
    }

    /// The read half: goes `false` after the client sends its FIN (half-close), which is the signal
    /// the relay turns into EOF on the outbound socket.
    pub fn may_recv(&self) -> bool {
        self.may_recv
    }

    /// The write half: stays `true` after the client's FIN, so a response can still be delivered.
    pub fn may_send(&self) -> bool {
        self.may_send
    }

    pub fn buffered(&self) -> usize {
        self.recv.len()
    }

    pub fn socket_handle(&self) -> SocketHandle {
        self.handle
    }
}

/// One bound UDP port. Datagrams for every destination share it; the original destination arrives
/// in `UdpMetadata::local_address`, which is what makes transparent UDP work without a socket per
/// destination.
pub(crate) struct UdpBinding {
    pub(crate) handle: SocketHandle,
    pub(crate) port: u16,
    pub(crate) rx_bytes: u64,
    pub(crate) tx_bytes: u64,
}

/// One datagram read out of a UDP binding, still carrying its original destination.
pub struct UdpDatagram {
    pub local: IpEndpoint,
    pub peer: IpEndpoint,
    pub payload: Vec<u8>,
}

/// Counters for the engine's `getStats` and for the tests. Deliberately plain `u64`s: the engine
/// publishes them through the existing JSON contract, it does not re-derive them from the stack.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Stats {
    pub packets_in: u64,
    pub packets_out: u64,
    pub bytes_in: u64,
    pub bytes_out: u64,
    pub malformed: u64,
    pub tcp_accepted: u64,
    pub tcp_rejected: u64,
    pub tcp_closed: u64,
    pub tcp_aborted_overflow: u64,
    pub tcp_expired: u64,
    pub udp_bound: u64,
    pub udp_rejected: u64,
    pub udp_datagrams_in: u64,
    pub udp_datagrams_out: u64,
}

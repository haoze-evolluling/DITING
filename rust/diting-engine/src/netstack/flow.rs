use std::collections::VecDeque;

use smoltcp::iface::SocketHandle;
use smoltcp::socket::tcp;
use smoltcp::time::Instant;
use smoltcp::wire::IpEndpoint;

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

pub struct TcpFlow {
    pub key: TcpKey,
    pub(crate) handle: SocketHandle,
    pub recv: VecDeque<u8>,
    pub(crate) state: tcp::State,
    pub(crate) may_recv: bool,
    pub(crate) may_send: bool,
    pub(crate) recv_closed: bool,
    pub(crate) eof_reported: bool,
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
            recv_closed: false,
            eof_reported: false,
            last_active: now,
            closed: false,
            rx_bytes: 0,
            tx_bytes: 0,
        }
    }

    pub fn state(&self) -> tcp::State {
        self.state
    }

    pub fn is_closed(&self) -> bool {
        self.closed
    }

    pub fn may_recv(&self) -> bool {
        self.may_recv
    }

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

pub(crate) struct UdpBinding {
    pub(crate) handle: SocketHandle,
    pub(crate) port: u16,
    pub(crate) rx_bytes: u64,
    pub(crate) tx_bytes: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UdpDatagram {
    pub local: IpEndpoint,
    pub peer: IpEndpoint,
    pub payload: Vec<u8>,
}

#[derive(Debug)]
pub struct FlowOutput {
    pub key: TcpKey,
    pub data: Vec<u8>,
    pub eof: bool,
    pub closed: bool,
}

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

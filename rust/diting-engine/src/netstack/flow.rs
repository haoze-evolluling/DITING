use std::collections::VecDeque;
use std::sync::Arc;

use smoltcp::iface::SocketHandle;
use smoltcp::socket::tcp;
use smoltcp::time::Instant;
use smoltcp::wire::IpEndpoint;
use tokio::sync::Semaphore;

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
    /// 上行数据按块排队。块的所有权直接在 smoltcp 的 socket 缓冲与流任务之间移动，
    /// 不再逐字节 `push_back`（旧实现一个字节一次环绕判断，并且取走时还要整段再拷一次）。
    recv: VecDeque<Vec<u8>>,
    /// `recv` 里的总字节数，随出入队维护，避免每次判断容量都遍历所有块。
    buffered: usize,
    pub(crate) state: tcp::State,
    pub(crate) may_recv: bool,
    pub(crate) may_send: bool,
    pub(crate) recv_closed: bool,
    pub(crate) eof_reported: bool,
    pub(crate) last_active: Instant,
    pub(crate) closed: bool,
    /// 上行信用窗口：按字节记账，只有上游真正写走后才归还，
    /// 让客户端 TCP 窗口随上游速度收缩，而不是在本地无限确认后 abort。
    pub(crate) upload: Option<Arc<Semaphore>>,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
}

impl TcpFlow {
    pub(crate) fn new(key: TcpKey, handle: SocketHandle, now: Instant) -> Self {
        Self {
            key,
            handle,
            recv: VecDeque::new(),
            buffered: 0,
            state: tcp::State::Listen,
            may_recv: true,
            may_send: true,
            recv_closed: false,
            eof_reported: false,
            last_active: now,
            closed: false,
            upload: None,
            rx_bytes: 0,
            tx_bytes: 0,
        }
    }

    pub(crate) fn push_chunk(&mut self, chunk: Vec<u8>) {
        if chunk.is_empty() {
            return;
        }
        self.buffered += chunk.len();
        self.recv.push_back(chunk);
    }

    /// 背压回退：把已取出的块按原顺序放回队首，O(1)，不再逐字节倒灌。
    pub(crate) fn push_chunk_front(&mut self, chunk: Vec<u8>) {
        if chunk.is_empty() {
            return;
        }
        self.buffered += chunk.len();
        self.recv.push_front(chunk);
    }

    /// 取走全部待上行数据：只有一个块时直接移出所有权，多块才合并。
    pub(crate) fn take_data(&mut self) -> Vec<u8> {
        self.buffered = 0;
        match self.recv.len() {
            0 => Vec::new(),
            1 => self.recv.pop_front().unwrap_or_default(),
            _ => {
                let mut merged = Vec::with_capacity(self.recv.iter().map(Vec::len).sum());
                for chunk in self.recv.drain(..) {
                    merged.extend_from_slice(&chunk);
                }
                merged
            }
        }
    }

    pub(crate) fn clear_recv(&mut self) {
        self.buffered = 0;
        self.recv.clear();
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
        self.buffered
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

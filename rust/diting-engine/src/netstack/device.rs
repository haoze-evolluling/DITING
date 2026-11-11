//! The packet side of the stack: an IP-medium device backed by two queues.
//!
//! This is the boundary the TUN adapter sits on. The real one copies from the `dup`ed TUN fd into
//! the receive queue and writes the transmit queue back out with the bounded writer and the
//! `ENETDOWN`/`EBUSY` retry policy from `tun_link_endpoint.go`; here both ends are plain
//! `VecDeque`s so the session can drive the stack without a device — and so the host tests can.
//!
//! The capability set is deliberately software-everything (`ChecksumCapabilities::default()`):
//! Android TUN devices do not offload checksums, so the stack must compute and verify them.

use std::collections::VecDeque;

use smoltcp::phy::{self, ChecksumCapabilities, Device, DeviceCapabilities, Medium};
use smoltcp::time::Instant;

pub struct IpDevice {
    rx: VecDeque<Vec<u8>>,
    tx: VecDeque<Vec<u8>>,
    mtu: usize,
}

impl IpDevice {
    pub fn new(mtu: usize) -> Self {
        Self {
            rx: VecDeque::new(),
            tx: VecDeque::new(),
            mtu,
        }
    }

    /// Queue one packet as if it had just been read from the TUN fd.
    pub fn push_rx(&mut self, packet: Vec<u8>) {
        self.rx.push_back(packet);
    }

    /// Take everything the stack wants to write to the TUN fd.
    pub fn drain_tx(&mut self) -> Vec<Vec<u8>> {
        self.tx.drain(..).collect()
    }

    pub fn pending_rx(&self) -> usize {
        self.rx.len()
    }
}

impl Device for IpDevice {
    type RxToken<'a> = RxToken;
    type TxToken<'a> = TxToken<'a>;

    fn capabilities(&self) -> DeviceCapabilities {
        let mut capabilities = DeviceCapabilities::default();
        capabilities.max_transmission_unit = self.mtu;
        capabilities.medium = Medium::Ip;
        capabilities.checksum = ChecksumCapabilities::default();
        capabilities
    }

    fn receive(&mut self, _timestamp: Instant) -> Option<(Self::RxToken<'_>, Self::TxToken<'_>)> {
        let buffer = self.rx.pop_front()?;
        let rx = RxToken { buffer };
        let tx = TxToken {
            queue: &mut self.tx,
        };
        Some((rx, tx))
    }

    fn transmit(&mut self, _timestamp: Instant) -> Option<Self::TxToken<'_>> {
        Some(TxToken {
            queue: &mut self.tx,
        })
    }
}

pub struct RxToken {
    buffer: Vec<u8>,
}

impl phy::RxToken for RxToken {
    fn consume<R, F>(self, f: F) -> R
    where
        F: FnOnce(&[u8]) -> R,
    {
        f(&self.buffer)
    }
}

pub struct TxToken<'a> {
    queue: &'a mut VecDeque<Vec<u8>>,
}

impl phy::TxToken for TxToken<'_> {
    fn consume<R, F>(self, len: usize, f: F) -> R
    where
        F: FnOnce(&mut [u8]) -> R,
    {
        let mut buffer = vec![0u8; len];
        let result = f(&mut buffer);
        self.queue.push_back(buffer);
        result
    }
}

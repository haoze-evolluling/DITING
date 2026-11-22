use std::collections::VecDeque;
use std::sync::{Condvar, Mutex};
use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LinkFault {
    Again,
    Backoff,
    Fatal,
}

pub trait PacketLink: Send + Sync + 'static {
    fn recv(&self, buffer: &mut [u8]) -> Result<usize, LinkFault>;

    fn send(&self, packet: &[u8]) -> Result<(), LinkFault>;

    fn mtu(&self) -> usize;

    fn close(&self);
}

#[derive(Default)]
pub struct MemoryLink {
    state: Mutex<MemoryState>,
    changed: Condvar,
    mtu: usize,
}

#[derive(Default)]
struct MemoryState {
    inbound: VecDeque<Vec<u8>>,
    outbound: Vec<Vec<u8>>,
    closed: bool,
}

impl MemoryLink {
    pub fn new(mtu: usize) -> Self {
        Self {
            mtu,
            ..Default::default()
        }
    }

    pub fn feed(&self, packet: Vec<u8>) {
        self.lock().inbound.push_back(packet);
        self.changed.notify_all();
    }

    pub fn wait_outbound(&self, timeout: Duration) -> Option<Vec<u8>> {
        let deadline = std::time::Instant::now() + timeout;
        let mut state = self.lock();
        loop {
            if let Some(packet) = state.outbound.first().cloned() {
                state.outbound.remove(0);
                return Some(packet);
            }
            let now = std::time::Instant::now();
            if now >= deadline {
                return None;
            }
            let (next, _) = self
                .changed
                .wait_timeout(state, deadline - now)
                .unwrap_or_else(|error| error.into_inner());
            state = next;
        }
    }

    pub fn take_outbound(&self) -> Vec<Vec<u8>> {
        std::mem::take(&mut self.lock().outbound)
    }

    pub fn outbound_len(&self) -> usize {
        self.lock().outbound.len()
    }

    pub fn is_closed(&self) -> bool {
        self.lock().closed
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, MemoryState> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

impl PacketLink for MemoryLink {
    fn recv(&self, buffer: &mut [u8]) -> Result<usize, LinkFault> {
        let mut state = self.lock();
        if state.closed {
            return Err(LinkFault::Fatal);
        }
        if state.inbound.is_empty() {
            let (next, _) = self
                .changed
                .wait_timeout(state, Duration::from_millis(50))
                .unwrap_or_else(|error| error.into_inner());
            state = next;
            if state.closed {
                return Err(LinkFault::Fatal);
            }
        }
        let Some(packet) = state.inbound.pop_front() else {
            return Err(LinkFault::Again);
        };
        let read = packet.len().min(buffer.len());
        buffer[..read].copy_from_slice(&packet[..read]);
        Ok(read)
    }

    fn send(&self, packet: &[u8]) -> Result<(), LinkFault> {
        let mut state = self.lock();
        if state.closed {
            return Err(LinkFault::Fatal);
        }
        state.outbound.push(packet.to_vec());
        drop(state);
        self.changed.notify_all();
        Ok(())
    }

    fn mtu(&self) -> usize {
        self.mtu
    }

    fn close(&self) {
        let mut state = self.lock();
        state.closed = true;
        drop(state);
        self.changed.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_packet_round_trips_through_both_directions() {
        let link = MemoryLink::new(1400);
        link.feed(vec![1, 2, 3]);
        let mut buffer = [0u8; 8];
        assert_eq!(link.recv(&mut buffer), Ok(3));
        assert_eq!(&buffer[..3], &[1, 2, 3]);
        assert!(link.send(&[9, 8]).is_ok());
        assert_eq!(
            link.wait_outbound(Duration::from_millis(100)),
            Some(vec![9, 8])
        );
    }

    #[test]
    fn closing_makes_the_next_read_fatal() {
        let link = MemoryLink::new(1400);
        link.close();
        let mut buffer = [0u8; 8];
        assert_eq!(link.recv(&mut buffer), Err(LinkFault::Fatal));
        assert_eq!(link.send(&[1]), Err(LinkFault::Fatal));
    }

    #[test]
    fn an_empty_link_reports_again_instead_of_blocking_forever() {
        let link = MemoryLink::new(1400);
        let mut buffer = [0u8; 8];
        assert_eq!(link.recv(&mut buffer), Err(LinkFault::Again));
    }
}

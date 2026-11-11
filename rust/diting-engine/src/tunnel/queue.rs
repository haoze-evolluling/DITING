//! The two queues the session needs: ingress events and egress packets.
//!
//! Go's `bufferedTun` used a 2048-slot channel with `sync.Pool`, a non-blocking send and a
//! drop-and-count policy: a full outbound queue must never stall the packet loop (TCP retransmits).
//! The ingress side had no queue at all because gVisor read the device directly; here the reader is
//! its own thread, so ingress needs the same bound and the same policy: drop the packet, count it.
//!
//! Commands from flow handlers (socket writes, close, DNS answers) share the ingress queue so the
//! stack thread has one place to wait on and one waker. They are not dropped: a lost command would
//! leave a flow parked forever.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use smoltcp::wire::IpEndpoint;
use tokio::sync::Semaphore;

use crate::netstack::TcpKey;

/// One unit of work for the stack thread.
#[derive(Debug)]
pub enum Event {
    /// A packet read from the TUN.
    Packet(Vec<u8>),
    /// Bytes the handler wants written to a TCP flow's client. The optional reservation is the
    /// per-flow write budget the producer acquired before queueing (relay flows only); the stack
    /// refunds it as bytes reach the socket, so the backlog stays bounded without truncating.
    Write(TcpKey, Vec<u8>, Option<Arc<Semaphore>>),
    /// The handler is done sending (FIN towards the client).
    CloseWrite(TcpKey),
    /// The handler gives up on the flow (RST).
    Abort(TcpKey),
    /// A datagram to send back to the client, from the original destination.
    Datagram {
        local: IpEndpoint,
        peer: IpEndpoint,
        payload: Vec<u8>,
    },
    /// A UDP relay task ended: forget its 4-tuple so the next datagram dials again.
    UdpExpire(TcpKey),
}

/// The bounded ingress queue.
pub struct Events {
    state: Mutex<EventsState>,
    changed: Condvar,
    capacity: usize,
    dropped: AtomicU64,
}

struct EventsState {
    events: VecDeque<Event>,
    closed: bool,
}

impl Events {
    pub fn new(capacity: usize) -> Self {
        Self {
            state: Mutex::new(EventsState {
                events: VecDeque::with_capacity(capacity),
                closed: false,
            }),
            changed: Condvar::new(),
            capacity,
            dropped: AtomicU64::new(0),
        }
    }

    /// Queues one packet, dropping it (and counting) when the queue is full.
    pub fn push_packet(&self, packet: Vec<u8>) {
        let mut state = self.lock();
        if state.closed {
            return;
        }
        if state.events.len() >= self.capacity {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        state.events.push_back(Event::Packet(packet));
        drop(state);
        self.changed.notify_one();
    }

    /// Queues one command (never dropped).
    pub fn push_command(&self, event: Event) {
        let mut state = self.lock();
        if state.closed {
            return;
        }
        state.events.push_back(event);
        drop(state);
        self.changed.notify_one();
    }

    /// Pops one event, waiting up to `timeout`. `None` on timeout or when the queue was closed.
    pub fn pop(&self, timeout: Duration) -> Option<Event> {
        let mut state = self.lock();
        if state.events.is_empty() && !state.closed {
            let (next, _) = self
                .changed
                .wait_timeout(state, timeout)
                .unwrap_or_else(|error| error.into_inner());
            state = next;
        }
        if state.closed {
            return None;
        }
        state.events.pop_front()
    }

    /// Wakes the stack thread and makes every later push a no-op.
    pub fn close(&self) {
        self.lock().closed = true;
        self.changed.notify_all();
    }

    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    pub fn len(&self) -> usize {
        self.lock().events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.lock().events.is_empty()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, EventsState> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

/// The bounded egress queue: stack thread → writer thread.
pub struct Egress {
    state: Mutex<EgressState>,
    changed: Condvar,
    capacity: usize,
    dropped: AtomicU64,
    closed: AtomicBool,
}

struct EgressState {
    packets: VecDeque<Vec<u8>>,
}

impl Egress {
    pub fn new(capacity: usize) -> Self {
        Self {
            state: Mutex::new(EgressState {
                packets: VecDeque::with_capacity(capacity),
            }),
            changed: Condvar::new(),
            capacity,
            dropped: AtomicU64::new(0),
            closed: AtomicBool::new(false),
        }
    }

    /// Queues one packet for the TUN, dropping it when the writer is behind.
    pub fn push(&self, packet: Vec<u8>) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        let mut state = self.lock();
        if state.packets.len() >= self.capacity {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        state.packets.push_back(packet);
        drop(state);
        self.changed.notify_one();
    }

    /// Pops one packet, waiting up to `timeout`.
    pub fn pop(&self, timeout: Duration) -> Option<Vec<u8>> {
        let mut state = self.lock();
        if state.packets.is_empty() && !self.closed.load(Ordering::Acquire) {
            let (next, _) = self
                .changed
                .wait_timeout(state, timeout)
                .unwrap_or_else(|error| error.into_inner());
            state = next;
        }
        state.packets.pop_front()
    }

    pub fn close(&self) {
        self.closed.store(true, Ordering::Release);
        self.changed.notify_all();
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }

    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    pub fn len(&self) -> usize {
        self.lock().packets.len()
    }

    pub fn is_empty(&self) -> bool {
        self.lock().packets.is_empty()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, EgressState> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_full_ingress_queue_drops_packets_instead_of_blocking() {
        let events = Events::new(2);
        events.push_packet(vec![1]);
        events.push_packet(vec![2]);
        events.push_packet(vec![3]);
        assert_eq!(events.dropped(), 1);
        assert_eq!(events.len(), 2);
        // Commands are never dropped, even when the queue is full.
        let key = TcpKey::new(
            "10.0.0.1:53".parse().expect("local"),
            "10.0.0.2:1234".parse().expect("remote"),
        );
        events.push_command(Event::Abort(key));
        assert_eq!(events.len(), 3);
    }

    #[test]
    fn a_full_egress_queue_drops_packets_instead_of_blocking_the_stack() {
        let egress = Egress::new(1);
        egress.push(vec![1]);
        egress.push(vec![2]);
        assert_eq!(egress.dropped(), 1);
        assert_eq!(egress.pop(Duration::ZERO), Some(vec![1]));
        assert_eq!(egress.pop(Duration::ZERO), None);
    }

    #[test]
    fn closing_wakes_a_waiting_consumer() {
        let events = std::sync::Arc::new(Events::new(4));
        let started = std::time::Instant::now();
        let closer = std::sync::Arc::clone(&events);
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(20));
            closer.close();
        });
        assert!(events.pop(Duration::from_secs(2)).is_none());
        assert!(started.elapsed() < Duration::from_secs(2));
    }
}

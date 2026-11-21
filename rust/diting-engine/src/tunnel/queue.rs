use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use smoltcp::wire::IpEndpoint;
use tokio::sync::Semaphore;

use crate::netstack::TcpKey;

const COMMAND_HIGH_WATER: usize = 16 * 1024;

#[derive(Debug)]
pub enum Event {
    Packet(Vec<u8>),
    Write(TcpKey, Vec<u8>, Option<Arc<Semaphore>>),
    CloseWrite(TcpKey),
    Abort(TcpKey),
    Datagram {
        local: IpEndpoint,
        peer: IpEndpoint,
        payload: Vec<u8>,
    },
    UdpExpire {
        key: TcpKey,
        generation: u64,
    },
}

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

    pub fn push_command(&self, event: Event) {
        let mut state = self.lock();
        if state.closed {
            return;
        }
        if state.events.len() >= COMMAND_HIGH_WATER && matches!(event, Event::Datagram { .. }) {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        state.events.push_back(event);
        drop(state);
        self.changed.notify_one();
    }

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

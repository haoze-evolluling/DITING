use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fault {
    Again,
    Backoff,
    Fatal,
}

pub trait PacketSource: Send + Sync {
    fn recv(&self, buf: &mut [u8]) -> Result<usize, Fault>;

    fn wake(&self);
}

pub trait PacketSink: Send + Sync {
    fn send(&self, packet: &[u8]) -> Result<usize, Fault>;
}

#[derive(Default)]
struct LoopbackState {
    queue: Mutex<VecDeque<Vec<u8>>>,
    ready: Condvar,
    closed: AtomicBool,
}

#[derive(Clone, Default)]
pub struct LoopbackHandle(Arc<LoopbackState>);

impl LoopbackHandle {
    pub fn new() -> LoopbackHandle {
        LoopbackHandle::default()
    }

    pub fn push(&self, packet: impl AsRef<[u8]>) -> bool {
        let mut queue = self.0.queue.lock().unwrap_or_else(|err| err.into_inner());
        if self.0.closed.load(Ordering::SeqCst) {
            return false;
        }
        queue.push_back(packet.as_ref().to_vec());
        drop(queue);
        self.0.ready.notify_one();
        true
    }

    pub fn len(&self) -> usize {
        self.0
            .queue
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn source(&self) -> LoopbackSource {
        LoopbackSource {
            shared: self.0.clone(),
        }
    }
}

pub struct LoopbackSource {
    shared: Arc<LoopbackState>,
}

impl PacketSource for LoopbackSource {
    fn recv(&self, buf: &mut [u8]) -> Result<usize, Fault> {
        let mut queue = self
            .shared
            .queue
            .lock()
            .unwrap_or_else(|err| err.into_inner());
        loop {
            if let Some(packet) = queue.pop_front() {
                let length = packet.len().min(buf.len());
                buf[..length].copy_from_slice(&packet[..length]);
                return Ok(length);
            }
            if self.shared.closed.load(Ordering::SeqCst) {
                return Err(Fault::Fatal);
            }
            queue = self
                .shared
                .ready
                .wait(queue)
                .unwrap_or_else(|err| err.into_inner());
        }
    }

    fn wake(&self) {
        self.shared.closed.store(true, Ordering::SeqCst);
        self.shared.ready.notify_all();
    }
}

impl LoopbackSource {
    pub fn close(&self) {
        self.wake();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn a_queued_packet_comes_back_byte_for_byte() {
        let handle = LoopbackHandle::new();
        let source = handle.source();
        assert!(handle.push([1u8, 2, 3, 4]));
        let mut buf = [0u8; 64];
        assert_eq!(source.recv(&mut buf), Ok(4));
        assert_eq!(&buf[..4], &[1, 2, 3, 4]);
    }

    #[test]
    fn a_packet_larger_than_the_buffer_is_truncated_like_read_two() {
        let handle = LoopbackHandle::new();
        let source = handle.source();
        handle.push(vec![7u8; 1500]);
        let mut buf = [0u8; 100];
        assert_eq!(source.recv(&mut buf), Ok(100));
    }

    #[test]
    fn wake_releases_a_blocked_reader_with_a_fatal_fault() {
        let handle = LoopbackHandle::new();
        let source = handle.source();
        let (tx, rx) = mpsc::channel();
        let reader = thread::spawn(move || {
            let mut buf = [0u8; 16];
            tx.send(source.recv(&mut buf)).ok();
        });

        thread::sleep(Duration::from_millis(50));
        handle.source().wake();
        assert_eq!(
            rx.recv_timeout(Duration::from_secs(2)),
            Ok(Err(Fault::Fatal))
        );
        reader.join().expect("the reader thread finishes");
    }

    #[test]
    fn a_closed_source_refuses_more_packets() {
        let handle = LoopbackHandle::new();
        handle.source().wake();
        assert!(!handle.push([1u8]));
    }
}

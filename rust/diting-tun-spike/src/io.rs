//! The packet boundary the data plane works against: one TUN read, one TUN write.
//!
//! Everything above this trait (the reader thread, the bounded queue, the worker that protects a
//! socket and dials, the callback dispatch) is device-independent, which is what makes the JNI and
//! threading model testable on a host. Two implementations exist:
//!
//! * [`crate::fd::FdSource`] / [`crate::fd::FdSink`] — the real Android TUN descriptor (unix only);
//! * [`LoopbackSource`] — an in-memory packet queue the host tests and the JVM smoke drive, so the
//!   same reader/worker/callback threads run without a device.
//!
//! A read returns exactly one packet, like `read(2)` on a TUN device. Faults are classified instead
//! of propagated raw, because the engine's policy differs per errno (`EAGAIN` retries immediately,
//! `ENETDOWN` backs off, `EBADF` stops the flow).

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};

/// Why a read or write did not produce a packet.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fault {
    /// Would block, or was interrupted: call again immediately (`EAGAIN`/`EWOULDBLOCK`/`EINTR`).
    Again,
    /// Temporarily unusable — `ENETDOWN`/`EBUSY`/`ENOBUFS` while the network switches: back off.
    Backoff,
    /// Nothing will arrive again (closed or invalid descriptor, end of the source): stop the reader.
    Fatal,
}

/// The read side of a TUN device.
///
/// `recv` takes `&self` so the reader thread can hold an `Arc` that `stop` also keeps a handle on:
/// `wake` has to be callable while `recv` is blocked. Implementations do their own interior
/// mutability.
pub trait PacketSource: Send + Sync {
    /// One blocking packet read into `buf`, returning the packet length.
    fn recv(&self, buf: &mut [u8]) -> Result<usize, Fault>;

    /// Makes a blocked `recv` return [`Fault::Fatal`] soon.
    ///
    /// The in-memory source notifies its condition variable. A TUN descriptor has no portable wake,
    /// which is why the engine closes its duplicated descriptor on stop (stage 3); the no-op here is
    /// deliberate, not an oversight.
    fn wake(&self);
}

/// The write side of a TUN device (upstream packets going back to the app).
pub trait PacketSink: Send + Sync {
    /// One packet write, returning how many bytes the device accepted.
    fn send(&self, packet: &[u8]) -> Result<usize, Fault>;
}

#[derive(Default)]
struct LoopbackState {
    queue: Mutex<VecDeque<Vec<u8>>>,
    ready: Condvar,
    closed: AtomicBool,
}

/// The producer handle of a [`LoopbackSource`]: what the tests and the JNI `feed` entry push into.
#[derive(Clone, Default)]
pub struct LoopbackHandle(Arc<LoopbackState>);

impl LoopbackHandle {
    pub fn new() -> LoopbackHandle {
        LoopbackHandle::default()
    }

    /// Queues one packet. Returns `false` once the source has been woken (stopped).
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

    /// How many packets are waiting to be read.
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

    /// The read side to hand to the pipeline.
    pub fn source(&self) -> LoopbackSource {
        LoopbackSource {
            shared: self.0.clone(),
        }
    }
}

/// An in-memory [`PacketSource`]: one queue, one condition variable, one closed flag.
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

        // The reader is parked on the condition variable; `wake` has to let it out.
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

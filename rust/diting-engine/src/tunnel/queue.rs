use std::collections::VecDeque;
use std::sync::atomic::{self, AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use smoltcp::wire::IpEndpoint;
use tokio::sync::Semaphore;

use crate::netstack::TcpKey;
use crate::tunnel::ring::BoundedRing;

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

/// 入站包与控制命令队列：
/// 读包路径和协程写回路径均走无锁有界环形缓冲；只有在消费者真的挂起休眠时才拿条件变量唤醒，
/// 消除原本每包一次 `Mutex + notify_one` 的串行化开销。
pub struct Events {
    packets: BoundedRing<Vec<u8>>,
    commands: BoundedRing<Event>,
    /// 极端突发下控制命令（Write/CloseWrite/Abort/UdpExpire）超过环形上限时的冷路径兜底。
    overflow: Mutex<VecDeque<Event>>,
    overflow_len: AtomicUsize,
    prefer_packet: AtomicBool,
    dropped: AtomicU64,
    closed: AtomicBool,
    sleeping: AtomicBool,
    wait_lock: Mutex<()>,
    wait_cv: Condvar,
}

impl Events {
    pub fn new(capacity: usize) -> Self {
        Self {
            packets: BoundedRing::new(capacity),
            commands: BoundedRing::new(COMMAND_HIGH_WATER),
            overflow: Mutex::new(VecDeque::new()),
            overflow_len: AtomicUsize::new(0),
            prefer_packet: AtomicBool::new(false),
            dropped: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            sleeping: AtomicBool::new(false),
            wait_lock: Mutex::new(()),
            wait_cv: Condvar::new(),
        }
    }

    pub fn push_packet(&self, packet: Vec<u8>) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        if self.packets.try_push(packet).is_err() {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        self.wake();
    }

    pub fn push_command(&self, event: Event) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        if matches!(event, Event::Datagram { .. }) && self.len() >= COMMAND_HIGH_WATER {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        if let Err(event) = self.commands.try_push(event) {
            if matches!(event, Event::Datagram { .. }) {
                self.dropped.fetch_add(1, Ordering::Relaxed);
                return;
            }
            let mut overflow = self
                .overflow
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            overflow.push_back(event);
            self.overflow_len.fetch_add(1, Ordering::Release);
        }
        self.wake();
    }

    pub fn pop(&self, timeout: Duration) -> Option<Event> {
        if self.closed.load(Ordering::Acquire) {
            return None;
        }
        if let Some(event) = self.try_pop() {
            return Some(event);
        }
        if timeout.is_zero() {
            return None;
        }

        let guard = self
            .wait_lock
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.sleeping.store(true, Ordering::SeqCst);
        if self.closed.load(Ordering::Acquire) {
            self.sleeping.store(false, Ordering::Relaxed);
            return None;
        }
        if let Some(event) = self.try_pop() {
            self.sleeping.store(false, Ordering::Relaxed);
            return Some(event);
        }
        let (_guard, _) = self
            .wait_cv
            .wait_timeout(guard, timeout)
            .unwrap_or_else(|error| error.into_inner());
        self.sleeping.store(false, Ordering::Relaxed);
        if self.closed.load(Ordering::Acquire) {
            return None;
        }
        self.try_pop()
    }

    pub fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        let _guard = self
            .wait_lock
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.wait_cv.notify_all();
    }

    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    pub fn len(&self) -> usize {
        self.packets.len() + self.commands.len() + self.overflow_len.load(Ordering::Acquire)
    }

    pub fn is_empty(&self) -> bool {
        self.packets.is_empty()
            && self.commands.is_empty()
            && self.overflow_len.load(Ordering::Acquire) == 0
    }

    fn try_pop(&self) -> Option<Event> {
        let packet_first = self.prefer_packet.fetch_xor(true, Ordering::Relaxed);
        if packet_first {
            self.packets
                .try_pop()
                .map(Event::Packet)
                .or_else(|| self.try_pop_command())
        } else {
            self.try_pop_command()
                .or_else(|| self.packets.try_pop().map(Event::Packet))
        }
    }

    fn try_pop_command(&self) -> Option<Event> {
        if let Some(event) = self.commands.try_pop() {
            return Some(event);
        }
        if self.overflow_len.load(Ordering::Acquire) == 0 {
            return None;
        }
        let mut overflow = self
            .overflow
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let event = overflow.pop_front()?;
        self.overflow_len.fetch_sub(1, Ordering::Release);
        Some(event)
    }

    #[inline]
    fn wake(&self) {
        // 与消费者 `sleeping.store(true, SeqCst)` 构成全序配对，确保绝不丢唤醒。
        atomic::fence(Ordering::SeqCst);
        if self.sleeping.load(Ordering::Relaxed) {
            let _guard = self
                .wait_lock
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            self.wait_cv.notify_one();
        }
    }
}

/// 出站包队列（单生产者：栈线程；单消费者：TUN 写线程）。
pub struct Egress {
    packets: BoundedRing<Vec<u8>>,
    dropped: AtomicU64,
    closed: AtomicBool,
    sleeping: AtomicBool,
    wait_lock: Mutex<()>,
    wait_cv: Condvar,
}

impl Egress {
    pub fn new(capacity: usize) -> Self {
        Self {
            packets: BoundedRing::new(capacity),
            dropped: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            sleeping: AtomicBool::new(false),
            wait_lock: Mutex::new(()),
            wait_cv: Condvar::new(),
        }
    }

    pub fn push(&self, packet: Vec<u8>) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        if self.packets.try_push(packet).is_err() {
            self.dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        self.wake();
    }

    pub fn pop(&self, timeout: Duration) -> Option<Vec<u8>> {
        if let Some(packet) = self.packets.try_pop() {
            return Some(packet);
        }
        if self.closed.load(Ordering::Acquire) || timeout.is_zero() {
            return self.packets.try_pop();
        }

        let guard = self
            .wait_lock
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.sleeping.store(true, Ordering::SeqCst);
        if let Some(packet) = self.packets.try_pop() {
            self.sleeping.store(false, Ordering::Relaxed);
            return Some(packet);
        }
        if self.closed.load(Ordering::Acquire) {
            self.sleeping.store(false, Ordering::Relaxed);
            return None;
        }
        let (_guard, _) = self
            .wait_cv
            .wait_timeout(guard, timeout)
            .unwrap_or_else(|error| error.into_inner());
        self.sleeping.store(false, Ordering::Relaxed);
        self.packets.try_pop()
    }

    pub fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        let _guard = self
            .wait_lock
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.wait_cv.notify_all();
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }

    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    pub fn len(&self) -> usize {
        self.packets.len()
    }

    pub fn is_empty(&self) -> bool {
        self.packets.is_empty()
    }

    #[inline]
    fn wake(&self) {
        atomic::fence(Ordering::SeqCst);
        if self.sleeping.load(Ordering::Relaxed) {
            let _guard = self
                .wait_lock
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            self.wait_cv.notify_one();
        }
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

    #[test]
    fn egress_wake_elision_never_misses_a_wakeup() {
        let egress = Arc::new(Egress::new(64));
        let producer = Arc::clone(&egress);
        let total = 2_000usize;
        let handle = std::thread::spawn(move || {
            for i in 0..total {
                producer.push((i as u32).to_le_bytes().to_vec());
                if i % 64 == 0 {
                    std::thread::sleep(Duration::from_micros(200));
                }
            }
        });
        let mut received = 0usize;
        while received < total {
            let packet = egress
                .pop(Duration::from_secs(2))
                .expect("producer must wake consumer");
            let value = u32::from_le_bytes(packet.try_into().unwrap()) as usize;
            assert_eq!(value, received);
            received += 1;
        }
        handle.join().unwrap();
    }
}

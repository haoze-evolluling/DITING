//! The data-plane skeleton end to end: reader thread, bounded queue, protected dial, callback thread.
//!
//! The packet source is the in-memory [`LoopbackSource`] (there is no Android TUN device on a host) and
//! the upstream is a real loopback TCP server, so the ordering claims — protect before connect,
//! packets written to the protected socket, callbacks from one thread, nothing after `stop` — are
//! observed rather than asserted from a comment.

use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use diting_tun_spike::callback::Dispatcher;
use diting_tun_spike::io::LoopbackHandle;
use diting_tun_spike::pipeline::{self, Config};
use diting_tun_spike::protector::Protector;
use diting_tun_spike::RawSocket;

/// An upstream that drains whatever the pipeline writes and counts the bytes.
struct Upstream {
    addr: SocketAddr,
    bytes: Arc<AtomicU64>,
    connections: Arc<AtomicU64>,
}

fn upstream() -> Upstream {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind the upstream");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("address");
    let bytes = Arc::new(AtomicU64::new(0));
    let connections = Arc::new(AtomicU64::new(0));
    let counter = bytes.clone();
    let accepted = connections.clone();
    std::thread::spawn(move || loop {
        match listener.accept() {
            Ok((stream, _peer)) => {
                accepted.fetch_add(1, Ordering::SeqCst);
                let counter = counter.clone();
                std::thread::spawn(move || drain(stream, counter));
            }
            Err(_) => std::thread::sleep(Duration::from_millis(5)),
        }
    });
    Upstream {
        addr,
        bytes,
        connections,
    }
}

fn drain(mut stream: TcpStream, counter: Arc<AtomicU64>) {
    use std::io::Read;
    let mut buf = [0u8; 4096];
    loop {
        match stream.read(&mut buf) {
            Ok(0) => return,
            Ok(read) => {
                counter.fetch_add(read as u64, Ordering::SeqCst);
            }
            Err(_) => return,
        }
    }
}

/// A protector that records the calls and can be told to refuse.
struct TestProtector {
    allow: AtomicBool,
    fd_positive: AtomicBool,
    calls: AtomicU64,
    delay: Mutex<Duration>,
}

impl TestProtector {
    fn new(allow: bool) -> Arc<TestProtector> {
        Arc::new(TestProtector {
            allow: AtomicBool::new(allow),
            fd_positive: AtomicBool::new(false),
            calls: AtomicU64::new(0),
            delay: Mutex::new(Duration::from_millis(0)),
        })
    }

    fn calls(&self) -> u64 {
        self.calls.load(Ordering::SeqCst)
    }
}

impl Protector for TestProtector {
    fn protect(&self, fd: RawSocket) -> bool {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.fd_positive.store(fd > 0, Ordering::SeqCst);
        let delay = *self.delay.lock().unwrap_or_else(|err| err.into_inner());
        if !delay.is_zero() {
            std::thread::sleep(delay);
        }
        self.allow.load(Ordering::SeqCst)
    }
}

fn callbacks(name: &str) -> Arc<Dispatcher> {
    Dispatcher::spawn(name, 1024, || |_payload: &str| {}).expect("spawn the callback thread")
}

fn wait_until(deadline: Duration, mut ready: impl FnMut() -> bool) -> bool {
    let until = Instant::now() + deadline;
    while Instant::now() < until {
        if ready() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    ready()
}

#[test]
fn packets_reach_the_protected_upstream_and_the_callback_thread() {
    let upstream = upstream();
    let source = LoopbackHandle::new();
    let protector = TestProtector::new(true);
    let dispatcher = callbacks("test-pipeline-one");
    let running = pipeline::start(
        Arc::new(source.source()),
        protector.clone(),
        Config::new(upstream.addr, 1500),
        dispatcher.clone(),
    )
    .expect("start the pipeline");

    let packets = 200u64;
    for sequence in 0..packets {
        assert!(source.push(vec![sequence as u8; 64]));
    }

    assert!(
        wait_until(Duration::from_secs(5), || {
            dispatcher.stats().delivered >= packets
        }),
        "callbacks arrived: {:?}",
        dispatcher.stats()
    );

    // One protected dial for the whole flow, and every packet written to it.
    assert_eq!(protector.calls(), 1, "protect runs once per connection");
    assert!(protector.fd_positive.load(Ordering::SeqCst));
    assert_eq!(running.evidence.protect_calls.load(Ordering::SeqCst), 1);
    assert_eq!(running.evidence.connects.load(Ordering::SeqCst), 1);
    assert!(running
        .evidence
        .protect_before_connect
        .load(Ordering::SeqCst));
    assert_eq!(running.counters.read.load(Ordering::SeqCst), packets);
    assert_eq!(running.counters.events.load(Ordering::SeqCst), packets);
    assert!(running.connection.get());
    assert!(running.error().is_none());

    assert!(
        wait_until(Duration::from_secs(5), || {
            upstream.bytes.load(Ordering::SeqCst) >= packets * 64
        }),
        "the upstream received the packets: {}",
        upstream.bytes.load(Ordering::SeqCst)
    );
    assert_eq!(upstream.connections.load(Ordering::SeqCst), 1);

    running.stop();
    let delivered = dispatcher.stats().delivered;
    // `stop` closed the source (push is refused) and joined the worker before closing the callback
    // thread, so nothing can be delivered afterwards.
    assert!(!source.push(vec![0u8; 64]));
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(dispatcher.stats().delivered, delivered);
    assert!(!running.connection.get());
}

#[test]
fn a_refused_protect_stops_the_pipeline_without_dialling() {
    let upstream = upstream();
    let source = LoopbackHandle::new();
    let protector = TestProtector::new(false);
    let dispatcher = callbacks("test-pipeline-refused");
    let running = pipeline::start(
        Arc::new(source.source()),
        protector.clone(),
        Config::new(upstream.addr, 1500),
        dispatcher.clone(),
    )
    .expect("start the pipeline");

    assert!(source.push(vec![1u8; 64]));

    assert!(
        wait_until(Duration::from_secs(5), || running.error().is_some()),
        "the pipeline reports the refusal"
    );
    let error = running.error().expect("an error");
    assert!(error.contains("protect"), "got {error}");
    assert_eq!(running.evidence.denied.load(Ordering::SeqCst), 1);
    assert_eq!(running.evidence.connects.load(Ordering::SeqCst), 0);
    assert_eq!(dispatcher.stats().delivered, 0);
    // Fail closed: no connection ever reached the upstream.
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(upstream.connections.load(Ordering::SeqCst), 0);

    running.stop();
}

#[test]
fn a_full_queue_drops_packets_instead_of_blocking_the_reader() {
    let upstream = upstream();
    let source = LoopbackHandle::new();
    let protector = TestProtector::new(true);
    // The worker is busy in `protect` for 150 ms; a queue of one cannot hold the burst.
    *protector
        .delay
        .lock()
        .unwrap_or_else(|err| err.into_inner()) = Duration::from_millis(150);
    let dispatcher = callbacks("test-pipeline-full");
    let mut config = Config::new(upstream.addr, 1500);
    config.queue_capacity = 1;
    let running = pipeline::start(
        Arc::new(source.source()),
        protector.clone(),
        config,
        dispatcher.clone(),
    )
    .expect("start the pipeline");

    let started = Instant::now();
    for _ in 0..100 {
        source.push(vec![2u8; 64]);
    }
    // Feeding must never block on the worker.
    assert!(started.elapsed() < Duration::from_secs(2));
    assert!(
        wait_until(Duration::from_secs(5), || {
            running.counters.read.load(Ordering::SeqCst) == 100
        }),
        "the reader drained the device"
    );
    assert!(
        running.counters.dropped.load(Ordering::SeqCst) > 0,
        "a capacity-1 queue must have dropped something"
    );

    running.stop();
}

#[test]
fn stop_is_idempotent_and_joins_every_thread() {
    let upstream = upstream();
    let source = LoopbackHandle::new();
    let dispatcher = callbacks("test-pipeline-stop");
    let running = pipeline::start(
        Arc::new(source.source()),
        TestProtector::new(true),
        Config::new(upstream.addr, 1500),
        dispatcher.clone(),
    )
    .expect("start the pipeline");

    running.stop();
    running.stop();
    // The callback thread is gone, so a dispatch is a counted drop rather than a hang.
    assert!(!dispatcher.dispatch("late".to_string()));
    assert_eq!(dispatcher.stats().dropped, 1);
}

#[test]
fn dropping_the_handle_stops_the_pipeline_the_same_way() {
    let upstream = upstream();
    let source = LoopbackHandle::new();
    let dispatcher = callbacks("test-pipeline-drop");
    {
        let running = pipeline::start(
            Arc::new(source.source()),
            TestProtector::new(true),
            Config::new(upstream.addr, 1500),
            dispatcher.clone(),
        )
        .expect("start the pipeline");
        source.push(vec![3u8; 64]);
        assert!(wait_until(Duration::from_secs(5), || dispatcher
            .stats()
            .delivered
            >= 1));
        drop(running);
    }
    let delivered = dispatcher.stats().delivered;
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(dispatcher.stats().delivered, delivered);
}

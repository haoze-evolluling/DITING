//! The TUN session: reader, stack and writer threads, and the flow handlers between them.
//!
//! Go ran the whole data plane inside gVisor's dispatcher goroutine plus one goroutine per flow.
//! Rust has no gVisor, so the equivalents are explicit:
//!
//! ```text
//! diting-tun-reader   read(2) → bounded ingress queue (drop + count on overflow)
//! diting-tun-stack    queue → Netstack → flow handlers, egress queue
//! diting-tun-writer   egress queue → write(2) with the 40-attempt backoff retry
//! tokio worker(s)     DNS queries (one task per datagram / TCP connection)
//! ```
//!
//! # Why three threads
//!
//! * The reader must block in `poll(2)` and cannot share a thread with the stack.
//! * The writer must absorb `ENETDOWN`/`EBUSY` during a handover (up to 40 retries) without
//!   stalling the stack's poll loop, which owns TCP timers. Go had the same split (`bufferedTun`'s
//!   drain goroutine behind a 2048-slot channel).
//! * The stack thread owns `smoltcp` (`Interface` is `!Sync`) and is woken by the queue's condvar
//!   for ingress packets, handler commands and its own `poll_delay` timer.
//!
//! # Stop order
//!
//! `stop` sets the flag, closes the link (waking the reader), closes both queues, then joins
//! **reader → stack → writer**. The stack thread drops the flow channels on its way out, so the
//! handler tasks end (a channel receiver never yields again) before the writer is joined. This is
//! the same "no callback after stop" property the JNI spike pinned for the callback thread.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use tokio::sync::{mpsc, Semaphore};

use crate::attribution::{PROTOCOL_TCP, PROTOCOL_UDP};
use crate::engine::Engine;
use crate::netstack::{self, Limits, Netstack, Stats, TcpKey};
use crate::tunnel::dnsflow::{self, Inbound};
use crate::tunnel::gate::{self, FlowAction, FlowContext};
use crate::tunnel::link::{LinkFault, PacketLink};
use crate::tunnel::queue::{Egress, Event, Events};
use crate::tunnel::relay;
use crate::tunnel::stats::TunnelCounters;
use crate::tunnel::writeback::{WriteBacklog, MAX_PENDING_WRITE};

/// The TUN write queue depth, from `tunWriteQueueDepth`.
pub const INGRESS_QUEUE: usize = 2048;
/// The same depth for egress; both are "one second of a busy phone", not a bandwidth promise.
pub const EGRESS_QUEUE: usize = 2048;
/// Packets one handler may have queued before the stack aborts the flow (backpressure, not growth).
const FLOW_CHANNEL: usize = 64;
/// `tunWriteRetryAttempts`.
const WRITE_ATTEMPTS: u32 = 40;
/// `tunWriteRetryBaseWait`.
const WRITE_BASE_WAIT: Duration = Duration::from_millis(5);
/// `tunWriteRetryMaxWait`.
const WRITE_MAX_WAIT: Duration = Duration::from_millis(100);
/// The reader's `Backoff` ladder during a handover.
const READER_BACKOFF_BASE: Duration = Duration::from_millis(1);
const READER_BACKOFF_MAX: Duration = Duration::from_millis(200);
/// The longest the stack thread sleeps without polling (also bounds stop latency).
const MAX_POLL_INTERVAL: Duration = Duration::from_millis(50);

/// A running TUN session.
pub struct Session {
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    egress: Arc<Egress>,
    link: Arc<dyn PacketLink>,
    counters: Arc<TunnelCounters>,
    stack_stats: Arc<Mutex<Stats>>,
    threads: Vec<JoinHandle<()>>,
}

impl Session {
    /// Starts the three threads. `link` is the real TUN fd or the in-memory test link.
    pub fn start(engine: Arc<Engine>, link: Arc<dyn PacketLink>) -> Result<Self, String> {
        let mtu = link.mtu().clamp(576, 65535);
        let limits = Limits {
            mtu,
            ..Limits::default()
        };
        let stop = Arc::new(AtomicBool::new(false));
        let events = Arc::new(Events::new(INGRESS_QUEUE));
        let egress = Arc::new(Egress::new(EGRESS_QUEUE));
        let counters = Arc::new(TunnelCounters::default());
        let stack_stats = Arc::new(Mutex::new(Stats::default()));

        let reader = spawn_reader(
            Arc::clone(&link),
            Arc::clone(&stop),
            Arc::clone(&events),
            Arc::clone(&counters),
        )?;
        let writer = spawn_writer(
            Arc::clone(&link),
            Arc::clone(&stop),
            Arc::clone(&egress),
            Arc::clone(&counters),
        )?;
        let stack = spawn_stack(
            engine,
            Arc::clone(&stop),
            Arc::clone(&events),
            Arc::clone(&egress),
            Arc::clone(&counters),
            Arc::clone(&stack_stats),
            limits,
        )?;

        Ok(Self {
            stop,
            events,
            egress,
            link,
            counters,
            stack_stats,
            threads: vec![reader, stack, writer],
        })
    }

    /// The `"tun"` document `getStats` carries.
    pub fn document(&self) -> serde_json::Value {
        let stats = *self
            .stack_stats
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.counters.document(stats)
    }

    pub fn is_running(&self) -> bool {
        !self.stop.load(Ordering::Acquire)
    }

    /// Stops every thread. Idempotent: `Drop` runs the same path.
    pub fn stop(mut self) {
        self.shutdown();
    }

    fn shutdown(&mut self) {
        if self.stop.swap(true, Ordering::AcqRel) {
            return;
        }
        // Link first: a reader parked in `poll(2)` only wakes because the dup is closed.
        self.link.close();
        self.events.close();
        self.egress.close();
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn spawn_reader(
    link: Arc<dyn PacketLink>,
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
) -> Result<JoinHandle<()>, String> {
    thread::Builder::new()
        .name("diting-tun-reader".to_string())
        .spawn(move || {
            // One byte past the MTU detects an oversized packet the same way `tun_link_endpoint`
            // did: read it, see it does not fit, drop it.
            let mut buffer = vec![0u8; link.mtu() + 1];
            let mut backoff = READER_BACKOFF_BASE;
            while !stop.load(Ordering::Acquire) {
                match link.recv(&mut buffer) {
                    Ok(read) => {
                        if read == 0 || read > link.mtu() {
                            continue;
                        }
                        backoff = READER_BACKOFF_BASE;
                        events.push_packet(buffer[..read].to_vec());
                    }
                    Err(LinkFault::Again) => {}
                    Err(LinkFault::Backoff) => {
                        thread::sleep(backoff);
                        backoff = (backoff * 2).min(READER_BACKOFF_MAX);
                    }
                    Err(LinkFault::Fatal) => break,
                }
            }
            counters
                .ingress_dropped
                .store(events.dropped(), Ordering::Relaxed);
        })
        .map_err(|error| format!("TUN reader thread: {error}"))
}

fn spawn_writer(
    link: Arc<dyn PacketLink>,
    stop: Arc<AtomicBool>,
    egress: Arc<Egress>,
    counters: Arc<TunnelCounters>,
) -> Result<JoinHandle<()>, String> {
    thread::Builder::new()
        .name("diting-tun-writer".to_string())
        .spawn(move || {
            // `healthy` mirrors Go's probe behaviour: after an exhausted retry budget the writer
            // tries each packet once until an interface write succeeds again, instead of paying the
            // full backoff per packet on a dead interface.
            let mut healthy = true;
            let mut backoff = WRITE_BASE_WAIT;
            while !stop.load(Ordering::Acquire) {
                let Some(packet) = egress.pop(Duration::from_millis(200)) else {
                    continue;
                };
                if !write_packet(
                    link.as_ref(),
                    &packet,
                    &stop,
                    &counters,
                    &mut healthy,
                    &mut backoff,
                ) {
                    return;
                }
            }
        })
        .map_err(|error| format!("TUN writer thread: {error}"))
}

/// Writes one packet with the retry ladder. `false` means the writer must stop.
fn write_packet(
    link: &dyn PacketLink,
    packet: &[u8],
    stop: &AtomicBool,
    counters: &TunnelCounters,
    healthy: &mut bool,
    backoff: &mut Duration,
) -> bool {
    let attempts = if *healthy { WRITE_ATTEMPTS } else { 1 };
    for attempt in 1..=attempts {
        match link.send(packet) {
            Ok(()) => {
                *healthy = true;
                *backoff = WRITE_BASE_WAIT;
                return true;
            }
            Err(LinkFault::Fatal) => {
                counters.write_failures.fetch_add(1, Ordering::Relaxed);
                return false;
            }
            Err(LinkFault::Again) | Err(LinkFault::Backoff) => {}
        }
        if attempt == attempts {
            *healthy = false;
            counters.write_failures.fetch_add(1, Ordering::Relaxed);
            // The interface is still there as far as we know: drop this packet, keep running, and
            // let TCP retransmit once the interface recovers.
            return true;
        }
        if stop.load(Ordering::Acquire) {
            return false;
        }
        counters.write_retries.fetch_add(1, Ordering::Relaxed);
        thread::sleep(*backoff);
        *backoff = (*backoff * 2).min(WRITE_MAX_WAIT);
    }
    true
}

/// One open TCP flow: the handler's inbound channel and its attribution.
struct Flow {
    tx: mpsc::Sender<Inbound>,
    context: FlowContext,
}

#[allow(clippy::too_many_arguments)]
fn spawn_stack(
    engine: Arc<Engine>,
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    egress: Arc<Egress>,
    counters: Arc<TunnelCounters>,
    stack_stats: Arc<Mutex<Stats>>,
    limits: Limits,
) -> Result<JoinHandle<()>, String> {
    thread::Builder::new()
        .name("diting-tun-stack".to_string())
        .spawn(move || {
            let mut net = Netstack::new(limits);
            let mut flows: HashMap<TcpKey, Flow> = HashMap::new();
            // One relay task per UDP 4-tuple, created on the first datagram.
            let mut udp_relays: HashMap<TcpKey, mpsc::Sender<Vec<u8>>> = HashMap::new();
            // Bytes the clients have not accepted yet, per TCP flow.
            let mut writes = WriteBacklog::default();

            while !stop.load(Ordering::Acquire) {
                let timeout = poll_timeout(&mut net);
                if let Some(event) = events.pop(timeout) {
                    handle_event(
                        &engine,
                        &counters,
                        &mut flows,
                        &mut udp_relays,
                        &mut writes,
                        &mut net,
                        event,
                    );
                    // Drain whatever else is queued without waiting: one poll per batch.
                    while let Some(event) = events.pop(Duration::ZERO) {
                        handle_event(
                            &engine,
                            &counters,
                            &mut flows,
                            &mut udp_relays,
                            &mut writes,
                            &mut net,
                            event,
                        );
                    }
                }

                let now = netstack::now();
                net.poll(now);
                // ACKs read in that poll may have reopened a client's send window.
                writes.flush_all(&mut net);
                for key in net.take_opened() {
                    counters.tcp_flows.fetch_add(1, Ordering::Relaxed);
                    open_tcp_flow(&engine, &events, &counters, &mut flows, &mut net, key);
                }
                dispatch_tcp_output(&engine, &counters, &mut flows, &mut writes, &mut net);
                while let Some(datagram) = net.udp_take() {
                    counters.udp_datagrams.fetch_add(1, Ordering::Relaxed);
                    dispatch_udp(&engine, &events, &counters, &mut udp_relays, datagram);
                }
                for packet in net.egress() {
                    egress.push(packet);
                }
                net.expire_idle(netstack::now());

                *stack_stats
                    .lock()
                    .unwrap_or_else(|error| error.into_inner()) = net.stats();
                counters
                    .ingress_dropped
                    .store(events.dropped(), Ordering::Relaxed);
                counters
                    .egress_dropped
                    .store(egress.dropped(), Ordering::Relaxed);
            }

            // The handler tasks end when their senders drop; the egress queue is closed by
            // `shutdown`, so nothing here can block.
            flows.clear();
            udp_relays.clear();
        })
        .map_err(|error| format!("TUN stack thread: {error}"))
}

/// The next `poll` deadline: the stack's timer, clamped so the loop can always notice `stop`.
fn poll_timeout(net: &mut Netstack) -> Duration {
    match net.poll_delay(netstack::now()) {
        Some(delay) => {
            let micros = delay.total_micros().max(1);
            Duration::from_micros(micros).min(MAX_POLL_INTERVAL)
        }
        None => MAX_POLL_INTERVAL,
    }
}

fn handle_event(
    engine: &Arc<Engine>,
    counters: &Arc<TunnelCounters>,
    flows: &mut HashMap<TcpKey, Flow>,
    udp_relays: &mut HashMap<TcpKey, mpsc::Sender<Vec<u8>>>,
    writes: &mut WriteBacklog,
    net: &mut Netstack,
    event: Event,
) {
    let now = netstack::now();
    match event {
        Event::Packet(packet) => net.ingress(&packet, now),
        Event::Write(key, data, credit) => {
            // A write that races with the flow's teardown must not resurrect a backlog no one will
            // ever drain; drop it. Otherwise queue it and refund the reserved budget as it is
            // written into the socket.
            if flows.contains_key(&key) && writes.enqueue(key, &data, credit, net) {
                // The safety cap was hit despite backpressure (a producer that never reserved):
                // reset the flow instead of silently truncating a TLS/HTTP stream.
                counters.short_writes.fetch_add(1, Ordering::Relaxed);
                net.tcp_abort(&key, netstack::now());
                net.tcp_remove(&key);
                flows.remove(&key);
                // `forget` closes the entry's reservation, waking a blocked relay reader.
                writes.forget(&key);
            }
        }
        Event::CloseWrite(key) => writes.close(key, net),
        Event::Abort(key) => {
            net.tcp_abort(&key, now);
            net.tcp_remove(&key);
            flows.remove(&key);
            // `forget` closes the entry's reservation, waking a blocked relay reader.
            writes.forget(&key);
        }
        Event::Datagram {
            local,
            peer,
            payload,
        } => {
            if net.udp_send(local, peer, &payload, now).is_err() {
                counters.udp_replies_dropped.fetch_add(1, Ordering::Relaxed);
            }
        }
        Event::UdpExpire(key) => {
            udp_relays.remove(&key);
        }
    }
    let _ = engine;
}

/// A SYN became a socket: decide, then serve DNS, intercept or relay.
fn open_tcp_flow(
    engine: &Arc<Engine>,
    events: &Arc<Events>,
    counters: &Arc<TunnelCounters>,
    flows: &mut HashMap<TcpKey, Flow>,
    net: &mut Netstack,
    key: TcpKey,
) {
    let context = gate::context_for(engine, PROTOCOL_TCP, key.remote, key.local);
    // With MITM running the same SYN goes through the `MODE_MITM_TCP` gate, which is what installs
    // the peek/decrypt path for `:80`/`:443` and keeps `:53` on the DNS pipeline.
    let action = if engine.mitm_state().active() {
        gate::admit_mitm_flow(engine, &key, &context)
    } else {
        gate::admit_flow(engine, true, &key, &context)
    };
    match action {
        FlowAction::HandleDns => {
            let (tx, rx) = mpsc::channel(FLOW_CHANNEL);
            let task_engine = Arc::clone(engine);
            let task_events = Arc::clone(events);
            let task_context = context.clone();
            task_engine.spawn(dnsflow::serve_tcp(
                Arc::clone(engine),
                task_events,
                key,
                rx,
                task_context,
            ));
            flows.insert(key, Flow { tx, context });
        }
        FlowAction::Intercept => {
            let (tx, rx) = mpsc::channel(FLOW_CHANNEL);
            let task_engine = Arc::clone(engine);
            let task_events = Arc::clone(events);
            let task_counters = Arc::clone(counters);
            let task_context = context.clone();
            task_engine.spawn(crate::mitm::handler::handle_tcp(
                Arc::clone(engine),
                task_events,
                task_counters,
                key,
                task_context,
                rx,
            ));
            flows.insert(key, Flow { tx, context });
            let _ = net;
        }
        FlowAction::Relay => {
            let (tx, rx) = mpsc::channel(FLOW_CHANNEL);
            let task_engine = Arc::clone(engine);
            let task_events = Arc::clone(events);
            let task_counters = Arc::clone(counters);
            // The relay reserves from this budget before reading each upstream chunk; the stack
            // refunds it as it writes into the socket, giving the downstream copy the same
            // blocking backpressure the Go engine had instead of an unbounded, abort-prone backlog.
            let credit = Arc::new(Semaphore::new(MAX_PENDING_WRITE));
            task_engine.spawn(relay::relay_tcp(
                Arc::clone(engine),
                task_events,
                task_counters,
                key,
                context.uid,
                rx,
                Arc::clone(&credit),
            ));
            flows.insert(key, Flow { tx, context });
            let _ = net;
        }
        FlowAction::Blocked => {
            counters.blocked_flows.fetch_add(1, Ordering::Relaxed);
            net.tcp_abort(&key, netstack::now());
            net.tcp_remove(&key);
        }
    }
}

/// Bytes read from the clients, and the closed flows.
fn dispatch_tcp_output(
    engine: &Arc<Engine>,
    counters: &Arc<TunnelCounters>,
    flows: &mut HashMap<TcpKey, Flow>,
    writes: &mut WriteBacklog,
    net: &mut Netstack,
) {
    for output in net.take_tcp_output() {
        let Some(flow) = flows.get(&output.key) else {
            if output.closed {
                net.tcp_remove(&output.key);
            }
            continue;
        };
        if !output.data.is_empty() {
            engine
                .traffic()
                .record(flow.context.uid, output.data.len() as i64, 0);
            if flow.tx.try_send(Inbound::Data(output.data)).is_err() {
                // The handler is not keeping up (or already exited): drop the flow rather than
                // buffer it without bound.
                counters.short_writes.fetch_add(1, Ordering::Relaxed);
                net.tcp_abort(&output.key, netstack::now());
                net.tcp_remove(&output.key);
                flows.remove(&output.key);
                writes.forget(&output.key);
                continue;
            }
        }
        if output.eof {
            let _ = flow.tx.try_send(Inbound::Eof);
        }
        if output.closed {
            flows.remove(&output.key);
            net.tcp_remove(&output.key);
            writes.forget(&output.key);
        }
    }
}

/// One datagram: gate, then either the DNS pipeline or a per-4-tuple relay.
fn dispatch_udp(
    engine: &Arc<Engine>,
    events: &Arc<Events>,
    counters: &Arc<TunnelCounters>,
    udp_relays: &mut HashMap<TcpKey, mpsc::Sender<Vec<u8>>>,
    datagram: crate::netstack::UdpDatagram,
) {
    let key = TcpKey::new(datagram.local, datagram.peer);
    let context = gate::context_for(engine, PROTOCOL_UDP, datagram.peer, datagram.local);
    match gate::admit_flow(engine, false, &key, &context) {
        FlowAction::HandleDns => {
            engine
                .traffic()
                .record(context.uid, datagram.payload.len() as i64, 0);
            let task_engine = Arc::clone(engine);
            let task_events = Arc::clone(events);
            task_engine.spawn(dnsflow::serve_udp(
                Arc::clone(engine),
                task_events,
                datagram,
                context,
            ));
        }
        FlowAction::Relay => {
            engine
                .traffic()
                .record(context.uid, datagram.payload.len() as i64, 0);
            // The relay task owns the upstream socket; this table only routes datagrams to it. A
            // send failure means the task already ended (idle timeout, upstream error), so the
            // entry is dropped and the datagram is lost the way a full socket's would be.
            let sender = udp_relays.entry(key).or_insert_with(|| {
                let (tx, rx) = mpsc::channel::<Vec<u8>>(FLOW_CHANNEL);
                let task_engine = Arc::clone(engine);
                let task_events = Arc::clone(events);
                let task_counters = Arc::clone(counters);
                task_engine.spawn(relay::relay_udp(
                    Arc::clone(engine),
                    task_events,
                    task_counters,
                    key,
                    context.uid,
                    rx,
                ));
                tx
            });
            if sender.try_send(datagram.payload).is_err() {
                udp_relays.remove(&key);
            }
        }
        FlowAction::Blocked => {
            counters.blocked_flows.fetch_add(1, Ordering::Relaxed);
        }
        // `MODE_FULL_UDP` never returns `Intercept`: datagrams are not intercepted, only relayed.
        FlowAction::Intercept => {}
    }
}

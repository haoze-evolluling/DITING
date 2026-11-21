use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use tokio::sync::{mpsc, Semaphore};
use tokio::task::JoinSet;

use crate::attribution::{PROTOCOL_TCP, PROTOCOL_UDP};
use crate::connection_limit::BucketKind;
use crate::engine::Engine;
use crate::netstack::{self, Limits, Netstack, Stats, TcpKey};
use crate::tunnel::dnsflow::{self, Inbound};
use crate::tunnel::gate::{self, FlowAction, FlowContext};
use crate::tunnel::link::{LinkFault, PacketLink};
use crate::tunnel::queue::{Egress, Event, Events};
use crate::tunnel::relay;
use crate::tunnel::stats::TunnelCounters;
use crate::tunnel::writeback::{WriteBacklog, MAX_PENDING_WRITE};

pub const INGRESS_QUEUE: usize = 2048;
pub const EGRESS_QUEUE: usize = 2048;
const FLOW_CHANNEL: usize = 64;
const WRITE_ATTEMPTS: u32 = 40;
const WRITE_BASE_WAIT: Duration = Duration::from_millis(5);
const WRITE_MAX_WAIT: Duration = Duration::from_millis(100);
const READER_BACKOFF_BASE: Duration = Duration::from_millis(1);
const READER_BACKOFF_MAX: Duration = Duration::from_millis(200);
const MAX_POLL_INTERVAL: Duration = Duration::from_millis(50);
const MAX_DNS_INFLIGHT: usize = 256;

type UdpRelays = HashMap<TcpKey, (u64, mpsc::Sender<Vec<u8>>)>;

pub struct Session {
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    egress: Arc<Egress>,
    link: Arc<dyn PacketLink>,
    counters: Arc<TunnelCounters>,
    stack_stats: Arc<Mutex<Stats>>,
    flow_tasks: Arc<Mutex<JoinSet<()>>>,
    threads: Vec<JoinHandle<()>>,
}

impl Session {
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
        let flow_tasks: Arc<Mutex<JoinSet<()>>> = Arc::new(Mutex::new(JoinSet::new()));
        let dns_permits = Arc::new(Semaphore::new(MAX_DNS_INFLIGHT));

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
            Arc::clone(&flow_tasks),
            dns_permits,
            limits,
        )?;

        Ok(Self {
            stop,
            events,
            egress,
            link,
            counters,
            stack_stats,
            flow_tasks,
            threads: vec![reader, stack, writer],
        })
    }

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

    pub fn stop(mut self) {
        self.shutdown();
    }

    fn shutdown(&mut self) {
        if self.stop.swap(true, Ordering::AcqRel) {
            return;
        }
        self.link.close();
        self.events.close();
        self.egress.close();
        self.abort_flows();
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
        self.abort_flows();
    }

    fn abort_flows(&self) {
        self.flow_tasks
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .abort_all();
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
    flow_tasks: Arc<Mutex<JoinSet<()>>>,
    dns_permits: Arc<Semaphore>,
    limits: Limits,
) -> Result<JoinHandle<()>, String> {
    thread::Builder::new()
        .name("diting-tun-stack".to_string())
        .spawn(move || {
            let mut net = Netstack::new(limits);
            let mut flows: HashMap<TcpKey, Flow> = HashMap::new();
            let mut udp_relays: UdpRelays = HashMap::new();
            let mut udp_generation = 0u64;
            let mut writes = WriteBacklog::default();

            while !stop.load(Ordering::Acquire) {
                reap_flows(&flow_tasks);
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
                writes.flush_all(&mut net);
                for key in net.take_opened() {
                    counters.tcp_flows.fetch_add(1, Ordering::Relaxed);
                    open_tcp_flow(
                        &engine,
                        &events,
                        &counters,
                        &flow_tasks,
                        &mut flows,
                        &mut net,
                        key,
                    );
                }
                dispatch_tcp_output(&engine, &counters, &mut flows, &mut writes, &mut net);
                while let Some(datagram) = net.udp_take() {
                    counters.udp_datagrams.fetch_add(1, Ordering::Relaxed);
                    dispatch_udp(
                        &engine,
                        &events,
                        &counters,
                        &flow_tasks,
                        &dns_permits,
                        &mut udp_relays,
                        &mut udp_generation,
                        datagram,
                    );
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

            flows.clear();
            udp_relays.clear();
        })
        .map_err(|error| format!("TUN stack thread: {error}"))
}

fn poll_timeout(net: &mut Netstack) -> Duration {
    match net.poll_delay(netstack::now()) {
        Some(delay) => {
            let micros = delay.total_micros().max(1);
            Duration::from_micros(micros).min(MAX_POLL_INTERVAL)
        }
        None => MAX_POLL_INTERVAL,
    }
}

fn spawn_flow(
    engine: &Arc<Engine>,
    flow_tasks: &Arc<Mutex<JoinSet<()>>>,
    future: impl std::future::Future<Output = ()> + Send + 'static,
) {
    flow_tasks
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .spawn_on(future, engine.runtime().handle());
}

fn reap_flows(flow_tasks: &Arc<Mutex<JoinSet<()>>>) {
    let mut tasks = flow_tasks
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    while tasks.try_join_next().is_some() {}
}

fn handle_event(
    engine: &Arc<Engine>,
    counters: &Arc<TunnelCounters>,
    flows: &mut HashMap<TcpKey, Flow>,
    udp_relays: &mut UdpRelays,
    writes: &mut WriteBacklog,
    net: &mut Netstack,
    event: Event,
) {
    let now = netstack::now();
    match event {
        Event::Packet(packet) => net.ingress(&packet, now),
        Event::Write(key, data, credit) => {
            if !flows.contains_key(&key) {
                if let Some(credit) = credit {
                    credit.close();
                }
            } else if writes.enqueue(key, &data, credit, net) {
                counters.short_writes.fetch_add(1, Ordering::Relaxed);
                net.tcp_abort(&key, netstack::now());
                net.tcp_remove(&key);
                flows.remove(&key);
                writes.forget(&key);
            }
        }
        Event::CloseWrite(key) => writes.close(key, net),
        Event::Abort(key) => {
            net.tcp_abort(&key, now);
            net.tcp_remove(&key);
            flows.remove(&key);
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
        Event::UdpExpire { key, generation } => {
            if udp_relays
                .get(&key)
                .is_some_and(|(current, _)| *current == generation)
            {
                udp_relays.remove(&key);
            }
        }
    }
    let _ = engine;
}

fn open_tcp_flow(
    engine: &Arc<Engine>,
    events: &Arc<Events>,
    counters: &Arc<TunnelCounters>,
    flow_tasks: &Arc<Mutex<JoinSet<()>>>,
    flows: &mut HashMap<TcpKey, Flow>,
    net: &mut Netstack,
    key: TcpKey,
) {
    let context = gate::context_for(engine, PROTOCOL_TCP, key.remote, key.local);
    let action = if engine.mitm_state().active() {
        gate::admit_mitm_flow(engine, &key, &context)
    } else {
        gate::admit_flow(engine, true, &key, &context)
    };
    if matches!(action, FlowAction::Relay | FlowAction::Intercept)
        && !engine.allow_connection_rate(
            BucketKind::Connection,
            context.uid,
            crate::resolver::now_ns(),
        )
    {
        counters.blocked_flows.fetch_add(1, Ordering::Relaxed);
        net.tcp_abort(&key, netstack::now());
        net.tcp_remove(&key);
        return;
    }
    match action {
        FlowAction::HandleDns => {
            let (tx, rx) = mpsc::channel(FLOW_CHANNEL);
            let task_events = Arc::clone(events);
            let task_context = context.clone();
            spawn_flow(
                engine,
                flow_tasks,
                dnsflow::serve_tcp(Arc::clone(engine), task_events, key, rx, task_context),
            );
            flows.insert(key, Flow { tx, context });
        }
        FlowAction::Intercept => {
            let (tx, rx) = mpsc::channel(FLOW_CHANNEL);
            let task_events = Arc::clone(events);
            let task_counters = Arc::clone(counters);
            let task_context = context.clone();
            spawn_flow(
                engine,
                flow_tasks,
                crate::mitm::handler::handle_tcp(
                    Arc::clone(engine),
                    task_events,
                    task_counters,
                    key,
                    task_context,
                    rx,
                ),
            );
            flows.insert(key, Flow { tx, context });
            let _ = net;
        }
        FlowAction::Relay => {
            let (tx, rx) = mpsc::channel(FLOW_CHANNEL);
            let task_events = Arc::clone(events);
            let task_counters = Arc::clone(counters);
            let credit = Arc::new(Semaphore::new(MAX_PENDING_WRITE));
            let upload = Arc::new(Semaphore::new(relay::UPLOAD_WINDOW));
            net.set_upload_gate(&key, Arc::clone(&upload));
            spawn_flow(
                engine,
                flow_tasks,
                relay::relay_tcp(
                    Arc::clone(engine),
                    task_events,
                    task_counters,
                    key,
                    context.uid,
                    rx,
                    Arc::clone(&credit),
                    Some(upload),
                ),
            );
            flows.insert(key, Flow { tx, context });
        }
        FlowAction::Blocked => {
            counters.blocked_flows.fetch_add(1, Ordering::Relaxed);
            net.tcp_abort(&key, netstack::now());
            net.tcp_remove(&key);
        }
    }
}

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
            let len = output.data.len();
            match flow.tx.try_send(Inbound::Data(output.data)) {
                Ok(()) => engine.traffic().record(flow.context.uid, len as i64, 0),
                // 流任务暂时落后：数据放回队首，下一轮再投递。
                // 这里不再 abort，避免上游一时拥塞就把连接打断。
                Err(mpsc::error::TrySendError::Full(Inbound::Data(data))) => {
                    counters
                        .upload_backpressure
                        .fetch_add(1, Ordering::Relaxed);
                    net.tcp_requeue(&output.key, data, output.eof);
                    continue;
                }
                // 流任务已经结束（或通道关闭）：连接没有接收方，直接清理。
                Err(_) => {
                    net.tcp_abort(&output.key, netstack::now());
                    net.tcp_remove(&output.key);
                    flows.remove(&output.key);
                    writes.forget(&output.key);
                    continue;
                }
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

fn dispatch_udp(
    engine: &Arc<Engine>,
    events: &Arc<Events>,
    counters: &Arc<TunnelCounters>,
    flow_tasks: &Arc<Mutex<JoinSet<()>>>,
    dns_permits: &Arc<Semaphore>,
    udp_relays: &mut UdpRelays,
    udp_generation: &mut u64,
    datagram: crate::netstack::UdpDatagram,
) {
    let key = TcpKey::new(datagram.local, datagram.peer);
    let context = gate::context_for(engine, PROTOCOL_UDP, datagram.peer, datagram.local);
    match gate::admit_flow(engine, false, &key, &context) {
        FlowAction::HandleDns => {
            if !engine.allow_connection_rate(
                BucketKind::Query,
                context.uid,
                crate::resolver::now_ns(),
            ) {
                return;
            }
            engine
                .traffic()
                .record(context.uid, datagram.payload.len() as i64, 0);
            let Ok(permit) = dns_permits.clone().try_acquire_owned() else {
                return;
            };
            let task_events = Arc::clone(events);
            let task_engine = Arc::clone(engine);
            spawn_flow(engine, flow_tasks, async move {
                let _permit = permit;
                dnsflow::serve_udp(task_engine, task_events, datagram, context).await;
            });
        }
        FlowAction::Relay => {
            if !udp_relays.contains_key(&key)
                && !engine.allow_connection_rate(
                    BucketKind::Connection,
                    context.uid,
                    crate::resolver::now_ns(),
                )
            {
                counters.blocked_flows.fetch_add(1, Ordering::Relaxed);
                return;
            }
            engine
                .traffic()
                .record(context.uid, datagram.payload.len() as i64, 0);
            let (_, sender) = udp_relays.entry(key).or_insert_with(|| {
                *udp_generation += 1;
                let generation = *udp_generation;
                let (tx, rx) = mpsc::channel::<Vec<u8>>(FLOW_CHANNEL);
                let task_events = Arc::clone(events);
                let task_counters = Arc::clone(counters);
                spawn_flow(
                    engine,
                    flow_tasks,
                    relay::relay_udp(
                        Arc::clone(engine),
                        task_events,
                        task_counters,
                        key,
                        context.uid,
                        generation,
                        rx,
                    ),
                );
                (generation, tx)
            });
            if sender.try_send(datagram.payload).is_err() {
                udp_relays.remove(&key);
            }
        }
        FlowAction::Blocked => {
            counters.blocked_flows.fetch_add(1, Ordering::Relaxed);
        }
        FlowAction::Intercept => {}
    }
}

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use tokio::sync::Semaphore;
use tokio::task::JoinSet;

use crate::engine::Engine;
use crate::netstack::{self, Netstack, Stats};
use crate::tunnel::queue::{Egress, Event, Events};
use crate::tunnel::stats::TunnelCounters;
use crate::tunnel::writeback::WriteBacklog;

use super::tasks::{reap_flows, Flow};
use super::tcp::{dispatch_tcp_output, open_tcp_flow};
use super::udp::dispatch_udp;
use super::UdpRelays;
use crate::netstack::TcpKey;
use std::collections::HashMap;

const MAX_POLL_INTERVAL: Duration = Duration::from_millis(50);

#[allow(clippy::too_many_arguments)]
pub(super) fn spawn_stack(
    engine: Arc<Engine>,
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    egress: Arc<Egress>,
    counters: Arc<TunnelCounters>,
    stack_stats: Arc<Mutex<Stats>>,
    flow_tasks: Arc<Mutex<JoinSet<()>>>,
    dns_permits: Arc<Semaphore>,
    limits: crate::netstack::Limits,
) -> Result<thread::JoinHandle<()>, String> {
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

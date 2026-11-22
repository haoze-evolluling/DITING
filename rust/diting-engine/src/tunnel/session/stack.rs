use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

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

const MAX_POLL_INTERVAL: Duration = Duration::from_millis(50);
/// 栈统计只被 UI 以秒级轮询读取，没必要每轮循环都抢一次锁去发布。
const STATS_PUBLISH_INTERVAL: Duration = Duration::from_millis(250);

#[allow(clippy::too_many_arguments)]
pub(super) fn spawn_stack(
    engine: Arc<Engine>,
    stop: Arc<AtomicBool>,
    events: Arc<Events>,
    egress: Arc<Egress>,
    counters: Arc<TunnelCounters>,
    stack_stats: Arc<Mutex<Stats>>,
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
            // 流任务表由本线程独占，热路径上不再有 `Mutex<JoinSet>`。
            let mut flow_tasks: JoinSet<()> = JoinSet::new();
            let mut last_publish = Instant::now();

            while !stop.load(Ordering::Acquire) {
                reap_flows(&mut flow_tasks);

                // 1) 先把队列里的事件全部消化掉。这里的每一步只改状态，不 poll。
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

                // 2) 整批入站包只 poll 一次：`Interface::poll` 会遍历整个 SocketSet，
                //    放在每个包上等于每包一次全表扫描。
                let now = netstack::now();
                net.poll(now);

                while let Some(key) = net.take_opened() {
                    counters.tcp_flows.fetch_add(1, Ordering::Relaxed);
                    open_tcp_flow(
                        &engine,
                        &events,
                        &counters,
                        &mut flow_tasks,
                        &mut flows,
                        &mut net,
                        key,
                    );
                }
                writes.flush_all(&mut net);
                dispatch_tcp_output(&engine, &counters, &mut flows, &mut writes, &mut net);
                while let Some(datagram) = net.udp_take() {
                    counters.udp_datagrams.fetch_add(1, Ordering::Relaxed);
                    dispatch_udp(
                        &engine,
                        &events,
                        &counters,
                        &mut flow_tasks,
                        &dns_permits,
                        &mut udp_relays,
                        &mut udp_generation,
                        datagram,
                    );
                }

                // 3) 再把这一轮写进 socket 的数据一次性发出去。
                net.poll(netstack::now());

                while let Some(packet) = net.take_egress() {
                    egress.push(packet);
                }
                net.expire_idle(netstack::now());

                if last_publish.elapsed() >= STATS_PUBLISH_INTERVAL {
                    last_publish = Instant::now();
                    *stack_stats
                        .lock()
                        .unwrap_or_else(|error| error.into_inner()) = net.stats();
                }
                counters
                    .ingress_dropped
                    .store(events.dropped(), Ordering::Relaxed);
                counters
                    .egress_dropped
                    .store(egress.dropped(), Ordering::Relaxed);
            }

            flow_tasks.abort_all();
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
        Event::Packet(packet) => net.ingress(packet, now),
        Event::Write(key, data, credit) => {
            if !flows.contains_key(&key) {
                if let Some(credit) = credit {
                    credit.close();
                }
            } else if writes.enqueue(key, &data, credit, net) {
                counters.short_writes.fetch_add(1, Ordering::Relaxed);
                net.tcp_abort_now(&key);
                net.tcp_remove(&key);
                flows.remove(&key);
                writes.forget(&key);
            }
        }
        Event::CloseWrite(key) => writes.close(key, net),
        Event::Abort(key) => {
            net.tcp_abort_now(&key);
            net.tcp_remove(&key);
            flows.remove(&key);
            writes.forget(&key);
        }
        Event::Datagram {
            local,
            peer,
            payload,
        } => {
            if net.udp_send_now(local, peer, &payload).is_err() {
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

use std::sync::atomic::Ordering;
use std::sync::Arc;

use tokio::sync::{mpsc, Semaphore};
use tokio::task::JoinSet;

use crate::attribution::PROTOCOL_UDP;
use crate::connection_limit::BucketKind;
use crate::engine::Engine;
use crate::netstack::TcpKey;
use crate::tunnel::gate;
use crate::tunnel::gate::FlowAction;
use crate::tunnel::queue::Events;
use crate::tunnel::relay;
use crate::tunnel::stats::TunnelCounters;

use super::tasks::spawn_flow;
use super::{UdpRelays, FLOW_CHANNEL};

#[allow(clippy::too_many_arguments)]
pub(super) fn dispatch_udp(
    engine: &Arc<Engine>,
    events: &Arc<Events>,
    counters: &Arc<TunnelCounters>,
    flow_tasks: &mut JoinSet<()>,
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
                crate::tunnel::dnsflow::serve_udp(task_engine, task_events, datagram, context)
                    .await;
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

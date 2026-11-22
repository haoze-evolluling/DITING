use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::sync::Arc;

use tokio::sync::{mpsc, Semaphore};
use tokio::task::JoinSet;

use crate::attribution::PROTOCOL_TCP;
use crate::connection_limit::BucketKind;
use crate::engine::Engine;
use crate::netstack::{Netstack, TcpKey};
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::gate::{self, FlowAction};
use crate::tunnel::relay;
use crate::tunnel::stats::TunnelCounters;
use crate::tunnel::writeback::{WriteBacklog, MAX_PENDING_WRITE};

use super::tasks::{spawn_flow, Flow};
use super::FLOW_CHANNEL;

#[allow(clippy::too_many_arguments)]
pub(super) fn open_tcp_flow(
    engine: &Arc<Engine>,
    events: &Arc<crate::tunnel::queue::Events>,
    counters: &Arc<TunnelCounters>,
    flow_tasks: &mut JoinSet<()>,
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
        net.tcp_abort_now(&key);
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
                crate::tunnel::dnsflow::serve_tcp(
                    Arc::clone(engine),
                    task_events,
                    key,
                    rx,
                    task_context,
                ),
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
            net.tcp_abort_now(&key);
            net.tcp_remove(&key);
        }
    }
}

pub(super) fn dispatch_tcp_output(
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
                    counters.upload_backpressure.fetch_add(1, Ordering::Relaxed);
                    net.tcp_requeue(&output.key, data, output.eof);
                    continue;
                }
                // 流任务已经结束（或通道关闭）：连接没有接收方，直接清理。
                Err(_) => {
                    net.tcp_abort_now(&output.key);
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
